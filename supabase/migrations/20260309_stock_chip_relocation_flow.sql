-- Stock relocation, chip approval workflow, and chip-sale exclusions.

ALTER TABLE public.stock_validations
ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES public.stores(id);

ALTER TABLE public.stok
ADD COLUMN IF NOT EXISTS relocation_status TEXT NOT NULL DEFAULT 'assigned'
  CHECK (relocation_status IN ('assigned', 'pending_claim')),
ADD COLUMN IF NOT EXISTS relocation_note TEXT,
ADD COLUMN IF NOT EXISTS relocation_reported_by UUID REFERENCES public.users(id),
ADD COLUMN IF NOT EXISTS relocation_reported_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS pending_chip_reason TEXT,
ADD COLUMN IF NOT EXISTS chip_requested_by UUID REFERENCES public.users(id),
ADD COLUMN IF NOT EXISTS chip_requested_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_stok_pending_claim
ON public.stok (relocation_status)
WHERE relocation_status = 'pending_claim' AND is_sold = false;

CREATE TABLE IF NOT EXISTS public.stock_chip_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stok_id UUID NOT NULL REFERENCES public.stok(id) ON DELETE CASCADE,
  store_id UUID REFERENCES public.stores(id),
  promotor_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sator_id UUID REFERENCES public.users(id),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES public.users(id),
  rejection_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_chip_requests_pending
ON public.stock_chip_requests (status, requested_at DESC);

ALTER TABLE public.stock_chip_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Promotor own chip requests" ON public.stock_chip_requests;
CREATE POLICY "Promotor own chip requests" ON public.stock_chip_requests
  FOR ALL USING (
    auth.uid() = promotor_id OR
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Sator team chip requests" ON public.stock_chip_requests;
CREATE POLICY "Sator team chip requests" ON public.stock_chip_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.hierarchy_sator_promotor hsp
      WHERE hsp.promotor_id = stock_chip_requests.promotor_id
        AND hsp.sator_id = auth.uid()
        AND hsp.active = true
    )
  );

DROP POLICY IF EXISTS "Sator approve team chip requests" ON public.stock_chip_requests;
CREATE POLICY "Sator approve team chip requests" ON public.stock_chip_requests
  FOR UPDATE USING (
    EXISTS (
      SELECT 1
      FROM public.hierarchy_sator_promotor hsp
      WHERE hsp.promotor_id = stock_chip_requests.promotor_id
        AND hsp.sator_id = auth.uid()
        AND hsp.active = true
    )
  );

DROP POLICY IF EXISTS "SPV area chip requests" ON public.stock_chip_requests;
CREATE POLICY "SPV area chip requests" ON public.stock_chip_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.users spv
      JOIN public.users promotor ON promotor.id = stock_chip_requests.promotor_id
      WHERE spv.id = auth.uid()
        AND spv.role = 'spv'
        AND spv.area = promotor.area
    )
  );

DROP POLICY IF EXISTS "Admin chip requests" ON public.stock_chip_requests;
CREATE POLICY "Admin chip requests" ON public.stock_chip_requests
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

CREATE OR REPLACE FUNCTION public.update_stock_chip_requests_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_stock_chip_requests_updated_at
ON public.stock_chip_requests;

CREATE TRIGGER trigger_update_stock_chip_requests_updated_at
  BEFORE UPDATE ON public.stock_chip_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_stock_chip_requests_updated_at();

ALTER TABLE public.sales_sell_out
ADD COLUMN IF NOT EXISTS stok_id UUID REFERENCES public.stok(id),
ADD COLUMN IF NOT EXISTS is_chip_sale BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS chip_label_visible BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_sales_sell_out_chip_sale
ON public.sales_sell_out (is_chip_sale, transaction_date DESC);

CREATE OR REPLACE FUNCTION public.report_stock_moved_out(
  p_stok_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_stock RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT s.*
  INTO v_stock
  FROM public.stok s
  WHERE s.id = p_stok_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock not found';
  END IF;

  IF v_stock.is_sold THEN
    RAISE EXCEPTION 'Stock already sold';
  END IF;

  UPDATE public.stok
  SET
    store_id = NULL,
    promotor_id = NULL,
    relocation_status = 'pending_claim',
    relocation_note = NULLIF(TRIM(COALESCE(p_note, '')), ''),
    relocation_reported_by = v_user_id,
    relocation_reported_at = NOW(),
    updated_at = NOW()
  WHERE id = p_stok_id;

  INSERT INTO public.stock_movement_log (
    stok_id,
    imei,
    from_store_id,
    to_store_id,
    movement_type,
    moved_by,
    moved_at,
    note
  ) VALUES (
    v_stock.id,
    v_stock.imei,
    v_stock.store_id,
    NULL,
    'adjustment',
    v_user_id,
    NOW(),
    COALESCE(NULLIF(TRIM(p_note), ''), 'Relocated out from store')
  );

  RETURN json_build_object(
    'success', true,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'status', 'pending_claim'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_relocated_stock(
  p_imei TEXT,
  p_variant_id UUID DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_store_id UUID;
  v_stock RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT aps.store_id
  INTO v_store_id
  FROM public.assignments_promotor_store aps
  WHERE aps.promotor_id = v_user_id
    AND aps.active = true
  ORDER BY aps.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'Promotor store assignment not found';
  END IF;

  SELECT s.*
  INTO v_stock
  FROM public.stok s
  WHERE s.imei = p_imei
    AND s.is_sold = false
    AND s.store_id IS NULL
    AND s.relocation_status = 'pending_claim'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relocated stock not found';
  END IF;

  IF p_variant_id IS NOT NULL AND v_stock.variant_id <> p_variant_id THEN
    RAISE EXCEPTION 'Variant mismatch for existing IMEI';
  END IF;

  UPDATE public.stok
  SET
    store_id = v_store_id,
    promotor_id = v_user_id,
    relocation_status = 'assigned',
    updated_at = NOW()
  WHERE id = v_stock.id;

  INSERT INTO public.stock_movement_log (
    stok_id,
    imei,
    from_store_id,
    to_store_id,
    movement_type,
    moved_by,
    moved_at,
    note
  ) VALUES (
    v_stock.id,
    v_stock.imei,
    NULL,
    v_store_id,
    'transfer_in',
    v_user_id,
    NOW(),
    COALESCE(NULLIF(TRIM(p_note), ''), 'Claimed relocated stock')
  );

  RETURN json_build_object(
    'success', true,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'store_id', v_store_id,
    'variant_id', v_stock.variant_id,
    'product_id', v_stock.product_id,
    'tipe_stok', v_stock.tipe_stok
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_chip_request(
  p_stok_id UUID,
  p_reason TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_stock RECORD;
  v_sator_id UUID;
  v_request_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Reason is required';
  END IF;

  SELECT s.*
  INTO v_stock
  FROM public.stok s
  WHERE s.id = p_stok_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock not found';
  END IF;

  IF v_stock.tipe_stok <> 'fresh' THEN
    RAISE EXCEPTION 'Only fresh stock can request chip status';
  END IF;

  SELECT hsp.sator_id
  INTO v_sator_id
  FROM public.hierarchy_sator_promotor hsp
  WHERE hsp.promotor_id = v_user_id
    AND hsp.active = true
  ORDER BY hsp.created_at DESC NULLS LAST
  LIMIT 1;

  INSERT INTO public.stock_chip_requests (
    stok_id,
    store_id,
    promotor_id,
    sator_id,
    reason
  ) VALUES (
    v_stock.id,
    v_stock.store_id,
    v_user_id,
    v_sator_id,
    TRIM(p_reason)
  )
  RETURNING id INTO v_request_id;

  UPDATE public.stok
  SET
    pending_chip_reason = TRIM(p_reason),
    chip_requested_by = v_user_id,
    chip_requested_at = NOW(),
    updated_at = NOW()
  WHERE id = v_stock.id;

  RETURN json_build_object(
    'success', true,
    'request_id', v_request_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.review_chip_request(
  p_request_id UUID,
  p_action TEXT,
  p_rejection_note TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_request RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF COALESCE(p_action, '') NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Action must be approved or rejected';
  END IF;

  SELECT r.*
  INTO v_request
  FROM public.stock_chip_requests r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  UPDATE public.stock_chip_requests
  SET
    status = p_action,
    approved_at = NOW(),
    approved_by = v_user_id,
    rejection_note = CASE WHEN p_action = 'rejected' THEN NULLIF(TRIM(COALESCE(p_rejection_note, '')), '') ELSE NULL END
  WHERE id = p_request_id;

  IF p_action = 'approved' THEN
    UPDATE public.stok
    SET
      tipe_stok = 'chip',
      chip_reason = v_request.reason,
      chip_approved_by = v_user_id,
      chip_approved_at = NOW(),
      pending_chip_reason = NULL,
      chip_requested_by = NULL,
      chip_requested_at = NULL,
      updated_at = NOW()
    WHERE id = v_request.stok_id;

    INSERT INTO public.stock_movement_log (
      stok_id,
      imei,
      movement_type,
      moved_by,
      moved_at,
      note
    )
    SELECT
      s.id,
      s.imei,
      'chip',
      v_user_id,
      NOW(),
      v_request.reason
    FROM public.stok s
    WHERE s.id = v_request.stok_id;
  ELSE
    UPDATE public.stok
    SET
      pending_chip_reason = NULL,
      chip_requested_by = NULL,
      chip_requested_at = NULL,
      updated_at = NOW()
    WHERE id = v_request.stok_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_store_chip_summary(
  p_store_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT json_build_object(
      'chip_count', COUNT(*)::INT,
      'items', COALESCE(
        json_agg(
          json_build_object(
            'stok_id', s.id,
            'imei', s.imei,
            'product_name', p.model_name,
            'network_type', p.network_type,
            'variant', pv.ram_rom,
            'color', pv.color,
            'chip_reason', s.chip_reason,
            'chip_approved_at', s.chip_approved_at,
            'chip_approved_by', approver.full_name
          )
          ORDER BY s.chip_approved_at DESC NULLS LAST, p.model_name
        ),
        '[]'::json
      )
    )
    FROM public.stok s
    JOIN public.product_variants pv ON pv.id = s.variant_id
    JOIN public.products p ON p.id = pv.product_id
    LEFT JOIN public.users approver ON approver.id = s.chip_approved_by
    WHERE s.store_id = p_store_id
      AND s.is_sold = false
      AND s.tipe_stok = 'chip'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.report_stock_moved_out(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_relocated_stock(TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_chip_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_chip_request(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_store_chip_summary(UUID) TO authenticated;
