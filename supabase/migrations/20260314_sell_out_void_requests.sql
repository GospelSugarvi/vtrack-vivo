-- Structured sell-out void flow:
-- promotor requests -> sator/spv/admin reviews -> backend performs atomic reversal.

CREATE TABLE IF NOT EXISTS public.sell_out_void_requests (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  sale_id UUID NOT NULL REFERENCES public.sales_sell_out(id) ON DELETE CASCADE,
  promotor_id UUID NOT NULL REFERENCES public.users(id),
  requested_by UUID NOT NULL REFERENCES public.users(id),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  review_note TEXT,
  reviewed_by UUID REFERENCES public.users(id),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_sell_out_void_requests_pending_sale
  ON public.sell_out_void_requests(sale_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_sell_out_void_requests_promotor_status
  ON public.sell_out_void_requests(promotor_id, status, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_sell_out_void_requests_status_requested_at
  ON public.sell_out_void_requests(status, requested_at DESC);

CREATE OR REPLACE FUNCTION public.set_sell_out_void_requests_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_sell_out_void_requests_updated_at ON public.sell_out_void_requests;
CREATE TRIGGER trg_set_sell_out_void_requests_updated_at
BEFORE UPDATE ON public.sell_out_void_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_sell_out_void_requests_updated_at();

ALTER TABLE public.sell_out_void_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Promotor read own void requests" ON public.sell_out_void_requests;
CREATE POLICY "Promotor read own void requests"
ON public.sell_out_void_requests
FOR SELECT
TO authenticated
USING (
  requested_by = auth.uid()
  OR promotor_id = auth.uid()
);

DROP POLICY IF EXISTS "Reviewer read team void requests" ON public.sell_out_void_requests;
CREATE POLICY "Reviewer read team void requests"
ON public.sell_out_void_requests
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role IN ('admin', 'manager')
  )
  OR EXISTS (
    SELECT 1
    FROM public.hierarchy_sator_promotor hsp
    WHERE hsp.promotor_id = sell_out_void_requests.promotor_id
      AND hsp.sator_id = auth.uid()
      AND hsp.active = true
  )
  OR EXISTS (
    SELECT 1
    FROM public.hierarchy_sator_promotor hsp
    JOIN public.hierarchy_spv_sator hss
      ON hss.sator_id = hsp.sator_id
     AND hss.active = true
    WHERE hsp.promotor_id = sell_out_void_requests.promotor_id
      AND hsp.active = true
      AND hss.spv_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Promotor insert own void request" ON public.sell_out_void_requests;
CREATE POLICY "Promotor insert own void request"
ON public.sell_out_void_requests
FOR INSERT
TO authenticated
WITH CHECK (
  requested_by = auth.uid()
  AND promotor_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.sales_sell_out so
    WHERE so.id = sale_id
      AND so.promotor_id = auth.uid()
      AND so.deleted_at IS NULL
  )
);

REVOKE UPDATE, DELETE, TRUNCATE ON public.sell_out_void_requests FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.request_sell_out_void(
  p_sale_id UUID,
  p_reason TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale RECORD;
  v_request_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_sale_id IS NULL THEN
    RAISE EXCEPTION 'p_sale_id is required';
  END IF;

  IF COALESCE(BTRIM(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  SELECT so.id, so.promotor_id, so.deleted_at, so.status, so.transaction_date
  INTO v_sale
  FROM public.sales_sell_out so
  WHERE so.id = p_sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaksi tidak ditemukan';
  END IF;

  IF v_sale.promotor_id <> auth.uid() THEN
    RAISE EXCEPTION 'Hanya promotor pemilik transaksi yang bisa mengajukan batal';
  END IF;

  IF v_sale.deleted_at IS NOT NULL OR COALESCE(v_sale.status, '') = 'void' THEN
    RAISE EXCEPTION 'Transaksi sudah dibatalkan';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.sell_out_void_requests r
    WHERE r.sale_id = p_sale_id
      AND r.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Pengajuan batal untuk transaksi ini masih diproses';
  END IF;

  INSERT INTO public.sell_out_void_requests (
    sale_id,
    promotor_id,
    requested_by,
    reason,
    status
  ) VALUES (
    p_sale_id,
    v_sale.promotor_id,
    auth.uid(),
    BTRIM(p_reason),
    'pending'
  )
  RETURNING id INTO v_request_id;

  RETURN json_build_object(
    'success', true,
    'request_id', v_request_id,
    'sale_id', p_sale_id,
    'status', 'pending'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sell_out_void_review_queue()
RETURNS TABLE (
  request_id UUID,
  sale_id UUID,
  promotor_id UUID,
  promotor_name TEXT,
  store_name TEXT,
  product_name TEXT,
  variant_name TEXT,
  price_at_transaction NUMERIC,
  transaction_date DATE,
  reason TEXT,
  status TEXT,
  requested_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT
    r.id AS request_id,
    so.id AS sale_id,
    so.promotor_id,
    u.full_name AS promotor_name,
    st.store_name,
    p.model_name AS product_name,
    CONCAT_WS(' ', NULLIF(pv.ram_rom, ''), NULLIF(pv.color, '')) AS variant_name,
    so.price_at_transaction,
    so.transaction_date,
    r.reason,
    r.status,
    r.requested_at
  FROM public.sell_out_void_requests r
  JOIN public.sales_sell_out so ON so.id = r.sale_id
  LEFT JOIN public.users u ON u.id = so.promotor_id
  LEFT JOIN public.stores st ON st.id = so.store_id
  LEFT JOIN public.product_variants pv ON pv.id = so.variant_id
  LEFT JOIN public.products p ON p.id = pv.product_id
  WHERE r.status = 'pending'
    AND (
      EXISTS (
        SELECT 1
        FROM public.users me
        WHERE me.id = auth.uid()
          AND me.role IN ('admin', 'manager')
      )
      OR EXISTS (
        SELECT 1
        FROM public.hierarchy_sator_promotor hsp
        WHERE hsp.promotor_id = so.promotor_id
          AND hsp.sator_id = auth.uid()
          AND hsp.active = true
      )
      OR EXISTS (
        SELECT 1
        FROM public.hierarchy_sator_promotor hsp
        JOIN public.hierarchy_spv_sator hss
          ON hss.sator_id = hsp.sator_id
         AND hss.active = true
        WHERE hsp.promotor_id = so.promotor_id
          AND hsp.active = true
          AND hss.spv_id = auth.uid()
      )
    )
  ORDER BY r.requested_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_sell_out_void_request(
  p_request_id UUID,
  p_action TEXT,
  p_review_note TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_actor_role TEXT;
  v_is_authorized BOOLEAN := false;
  v_old_status TEXT;
  v_period_id UUID;
  v_total_bonus NUMERIC := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'p_request_id is required';
  END IF;

  IF COALESCE(BTRIM(p_action), '') NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'p_action must be approved or rejected';
  END IF;

  SELECT
    r.*,
    so.promotor_id AS sale_promotor_id,
    so.store_id,
    so.variant_id,
    so.stok_id,
    so.serial_imei,
    so.transaction_date,
    so.price_at_transaction,
    so.status AS sale_status,
    so.deleted_at AS sale_deleted_at,
    so.is_chip_sale
  INTO v_request
  FROM public.sell_out_void_requests r
  JOIN public.sales_sell_out so ON so.id = r.sale_id
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request tidak ditemukan';
  END IF;

  IF v_request.status <> 'pending' THEN
    RAISE EXCEPTION 'Request ini sudah diproses';
  END IF;

  SELECT u.role::TEXT
  INTO v_actor_role
  FROM public.users u
  WHERE u.id = auth.uid();

  IF v_actor_role IN ('admin', 'manager') THEN
    v_is_authorized := true;
  ELSIF v_actor_role = 'sator' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.hierarchy_sator_promotor hsp
      WHERE hsp.promotor_id = v_request.promotor_id
        AND hsp.sator_id = auth.uid()
        AND hsp.active = true
    ) INTO v_is_authorized;
  ELSIF v_actor_role = 'spv' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.hierarchy_sator_promotor hsp
      JOIN public.hierarchy_spv_sator hss
        ON hss.sator_id = hsp.sator_id
       AND hss.active = true
      WHERE hsp.promotor_id = v_request.promotor_id
        AND hsp.active = true
        AND hss.spv_id = auth.uid()
    ) INTO v_is_authorized;
  END IF;

  IF NOT v_is_authorized THEN
    RAISE EXCEPTION 'Anda tidak berwenang mereview request ini';
  END IF;

  IF p_action = 'rejected' THEN
    UPDATE public.sell_out_void_requests
    SET
      status = 'rejected',
      review_note = NULLIF(BTRIM(COALESCE(p_review_note, '')), ''),
      reviewed_by = auth.uid(),
      reviewed_at = NOW()
    WHERE id = p_request_id;

    RETURN json_build_object(
      'success', true,
      'request_id', p_request_id,
      'status', 'rejected'
    );
  END IF;

  IF v_request.sale_deleted_at IS NOT NULL OR COALESCE(v_request.sale_status, '') = 'void' THEN
    RAISE EXCEPTION 'Transaksi sudah dibatalkan sebelumnya';
  END IF;

  v_old_status := COALESCE(v_request.sale_status, 'verified');

  UPDATE public.sales_sell_out
  SET
    status = 'void',
    deleted_at = NOW(),
    updated_at = NOW()
  WHERE id = v_request.sale_id;

  INSERT INTO public.sales_sell_out_status_history (
    sales_sell_out_id,
    old_status,
    new_status,
    notes,
    changed_by,
    changed_at
  ) VALUES (
    v_request.sale_id,
    v_old_status,
    'void',
    COALESCE(NULLIF(BTRIM(COALESCE(p_review_note, '')), ''), 'Voided from sell_out_void_request'),
    auth.uid(),
    NOW()
  );

  IF v_request.stok_id IS NOT NULL THEN
    UPDATE public.stok
    SET
      is_sold = false,
      sold_at = NULL,
      sold_price = NULL
    WHERE id = v_request.stok_id;

    INSERT INTO public.stock_movement_log (
      stok_id,
      imei,
      movement_type,
      moved_by,
      moved_at,
      note
    ) VALUES (
      v_request.stok_id,
      v_request.serial_imei,
      'sale_void',
      auth.uid(),
      NOW(),
      CONCAT('Void sell-out approved: ', COALESCE(NULLIF(BTRIM(COALESCE(p_review_note, '')), ''), v_request.reason))
    );
  END IF;

  INSERT INTO public.store_inventory (
    store_id,
    variant_id,
    quantity,
    last_updated
  ) VALUES (
    v_request.store_id,
    v_request.variant_id,
    1,
    NOW()
  )
  ON CONFLICT (store_id, variant_id)
  DO UPDATE SET
    quantity = public.store_inventory.quantity + 1,
    last_updated = NOW();

  SELECT tp.id
  INTO v_period_id
  FROM public.target_periods tp
  WHERE v_request.transaction_date BETWEEN tp.start_date AND tp.end_date
    AND COALESCE(tp.status, 'active') = 'active'
    AND tp.deleted_at IS NULL
  ORDER BY tp.start_date DESC
  LIMIT 1;

  SELECT COALESCE(SUM(sbe.bonus_amount), 0)
  INTO v_total_bonus
  FROM public.sales_bonus_events sbe
  WHERE sbe.sales_sell_out_id = v_request.sale_id;

  IF COALESCE(v_total_bonus, 0) <> 0 THEN
    INSERT INTO public.sales_bonus_events (
      sales_sell_out_id,
      user_id,
      period_id,
      bonus_type,
      rule_snapshot,
      bonus_amount,
      is_projection,
      calculation_version,
      notes,
      created_by
    ) VALUES (
      v_request.sale_id,
      v_request.promotor_id,
      v_period_id,
      'reversal',
      jsonb_build_object(
        'source', 'review_sell_out_void_request',
        'request_id', p_request_id,
        'reversed_bonus_total', v_total_bonus
      ),
      -1 * v_total_bonus,
      false,
      '20260314_sell_out_void_v1',
      'Automatic bonus reversal for voided sell-out',
      auth.uid()
    );
  END IF;

  UPDATE public.sell_out_void_requests
  SET
    status = 'approved',
    review_note = NULLIF(BTRIM(COALESCE(p_review_note, '')), ''),
    reviewed_by = auth.uid(),
    reviewed_at = NOW()
  WHERE id = p_request_id;

  RETURN json_build_object(
    'success', true,
    'request_id', p_request_id,
    'sale_id', v_request.sale_id,
    'status', 'approved'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_sell_out_void(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sell_out_void_review_queue() TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_sell_out_void_request(UUID, TEXT, TEXT) TO authenticated;
