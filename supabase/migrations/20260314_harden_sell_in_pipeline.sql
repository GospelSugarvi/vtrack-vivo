-- Harden sell-in pipeline so orders remain the source of truth
-- and sales_sell_in becomes a safe derived feed.

ALTER TABLE public.sales_sell_in
  ADD COLUMN IF NOT EXISTS source_order_id UUID REFERENCES public.sell_in_orders(id);

CREATE INDEX IF NOT EXISTS idx_sales_sell_in_source_order_id
  ON public.sales_sell_in(source_order_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_sell_in_order_variant_active
  ON public.sales_sell_in(source_order_id, variant_id)
  WHERE deleted_at IS NULL AND source_order_id IS NOT NULL;

UPDATE public.sales_sell_in si
SET source_order_id = substring(si.notes from 'Finalized order #([0-9a-f-]{36})')::uuid
WHERE si.deleted_at IS NULL
  AND si.source_order_id IS NULL
  AND si.notes ~ '^Finalized order #[0-9a-f-]{36} \(';

UPDATE public.sales_sell_in si
SET group_id = COALESCE(o.group_id, st.group_id)
FROM public.sell_in_orders o
LEFT JOIN public.stores st ON st.id = o.store_id
WHERE si.deleted_at IS NULL
  AND si.source_order_id = o.id
  AND si.group_id IS NULL;

INSERT INTO public.sell_in_order_status_history (
  order_id,
  old_status,
  new_status,
  notes,
  changed_at,
  changed_by
)
SELECT
  o.id,
  NULL,
  o.status,
  'Backfilled for legacy sell-in order',
  COALESCE(o.created_at, NOW()),
  COALESCE(o.finalized_by, o.sator_id)
FROM public.sell_in_orders o
LEFT JOIN public.sell_in_order_status_history h
  ON h.order_id = o.id
WHERE h.order_id IS NULL;

ALTER TABLE public.sales_sell_in ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sator Own Sell In Read" ON public.sales_sell_in;
CREATE POLICY "Sator Own Sell In Read"
ON public.sales_sell_in
FOR SELECT
TO authenticated
USING (sator_id = auth.uid());

DROP POLICY IF EXISTS "SPV Team Sell In Read" ON public.sales_sell_in;
CREATE POLICY "SPV Team Sell In Read"
ON public.sales_sell_in
FOR SELECT
TO authenticated
USING (
  sator_id IN (
    SELECT hss.sator_id
    FROM public.hierarchy_spv_sator hss
    WHERE hss.spv_id = auth.uid()
      AND hss.active = true
  )
);

DROP POLICY IF EXISTS "Admin All Sell In Read" ON public.sales_sell_in;
CREATE POLICY "Admin All Sell In Read"
ON public.sales_sell_in
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role = 'admin'
  )
);

REVOKE INSERT, UPDATE, DELETE ON public.sales_sell_in FROM anon, authenticated;
REVOKE TRUNCATE ON public.sales_sell_in FROM anon, authenticated;

DROP FUNCTION IF EXISTS public.finalize_sell_in_order(UUID,UUID,DATE,TEXT,TEXT,JSONB);
CREATE OR REPLACE FUNCTION public.finalize_sell_in_order(
  p_sator_id UUID,
  p_store_id UUID,
  p_order_date DATE,
  p_source TEXT,
  p_notes TEXT,
  p_items JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id UUID;
  v_total_items INTEGER := 0;
  v_total_qty INTEGER := 0;
  v_total_value NUMERIC := 0;
  v_store_name TEXT;
  v_group_id UUID;
BEGIN
  IF p_sator_id IS NULL OR p_store_id IS NULL THEN
    RAISE EXCEPTION 'p_sator_id and p_store_id are required';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items must be a JSON array';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_sator_id THEN
    RAISE EXCEPTION 'Unauthorized finalization context';
  END IF;

  IF COALESCE(p_source, '') NOT IN ('manual', 'recommendation') THEN
    RAISE EXCEPTION 'p_source must be manual or recommendation';
  END IF;

  WITH parsed AS (
    SELECT
      (x->>'variant_id')::UUID AS variant_id,
      GREATEST(COALESCE((x->>'qty')::INTEGER, 0), 0) AS qty
    FROM jsonb_array_elements(p_items) x
  ),
  valid AS (
    SELECT
      p.variant_id,
      p.qty,
      pv.srp::NUMERIC AS price,
      (p.qty * pv.srp::NUMERIC) AS subtotal
    FROM parsed p
    JOIN public.product_variants pv ON pv.id = p.variant_id
    JOIN public.products pr ON pr.id = pv.product_id
    WHERE p.qty > 0
      AND pv.active = true
      AND pr.status = 'active'
  )
  SELECT
    COUNT(*)::INTEGER,
    COALESCE(SUM(qty), 0)::INTEGER,
    COALESCE(SUM(subtotal), 0)::NUMERIC
  INTO v_total_items, v_total_qty, v_total_value
  FROM valid;

  IF v_total_items = 0 OR v_total_qty = 0 THEN
    RAISE EXCEPTION 'No valid order items to finalize';
  END IF;

  SELECT st.store_name, st.group_id
  INTO v_store_name, v_group_id
  FROM public.stores st
  WHERE st.id = p_store_id;

  INSERT INTO public.sell_in_orders (
    sator_id,
    store_id,
    group_id,
    order_date,
    source,
    status,
    notes,
    total_items,
    total_qty,
    total_value,
    finalized_at,
    finalized_by
  ) VALUES (
    p_sator_id,
    p_store_id,
    v_group_id,
    COALESCE(p_order_date, CURRENT_DATE),
    p_source,
    'finalized',
    p_notes,
    v_total_items,
    v_total_qty,
    v_total_value,
    NOW(),
    p_sator_id
  )
  RETURNING id INTO v_order_id;

  INSERT INTO public.sell_in_order_status_history (
    order_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) VALUES (
    v_order_id,
    NULL,
    'finalized',
    'Created by finalize_sell_in_order',
    p_sator_id
  );

  WITH parsed AS (
    SELECT
      (x->>'variant_id')::UUID AS variant_id,
      GREATEST(COALESCE((x->>'qty')::INTEGER, 0), 0) AS qty
    FROM jsonb_array_elements(p_items) x
  ),
  valid AS (
    SELECT
      p.variant_id,
      p.qty,
      pv.srp::NUMERIC AS price,
      (p.qty * pv.srp::NUMERIC) AS subtotal
    FROM parsed p
    JOIN public.product_variants pv ON pv.id = p.variant_id
    JOIN public.products pr ON pr.id = pv.product_id
    WHERE p.qty > 0
      AND pv.active = true
      AND pr.status = 'active'
  )
  INSERT INTO public.sell_in_order_items (order_id, variant_id, qty, price, subtotal)
  SELECT v_order_id, variant_id, qty, price, subtotal
  FROM valid;

  INSERT INTO public.sales_sell_in (
    sator_id,
    store_id,
    group_id,
    source_order_id,
    variant_id,
    transaction_date,
    qty,
    total_value,
    notes
  )
  SELECT
    p_sator_id,
    p_store_id,
    v_group_id,
    v_order_id,
    i.variant_id,
    COALESCE(p_order_date, CURRENT_DATE),
    i.qty,
    i.subtotal,
    CONCAT('Finalized order #', v_order_id::TEXT, ' (', p_source, ')')
  FROM public.sell_in_order_items i
  WHERE i.order_id = v_order_id;

  RETURN json_build_object(
    'success', true,
    'order_id', v_order_id,
    'store_id', p_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'group_id', v_group_id,
    'order_date', COALESCE(p_order_date, CURRENT_DATE),
    'source', p_source,
    'status', 'finalized',
    'total_items', v_total_items,
    'total_qty', v_total_qty,
    'total_value', v_total_value,
    'finalized_at', NOW()
  );
END;
$$;

DROP FUNCTION IF EXISTS public.finalize_sell_in_order_by_id(UUID,UUID,TEXT);
CREATE OR REPLACE FUNCTION public.finalize_sell_in_order_by_id(
  p_sator_id UUID,
  p_order_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
BEGIN
  IF p_sator_id IS NULL OR p_order_id IS NULL THEN
    RAISE EXCEPTION 'p_sator_id and p_order_id are required';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_sator_id THEN
    RAISE EXCEPTION 'Unauthorized finalization context';
  END IF;

  SELECT * INTO v_order
  FROM public.sell_in_orders o
  WHERE o.id = p_order_id
    AND o.sator_id = p_sator_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found for this user';
  END IF;

  IF v_order.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending order can be finalized';
  END IF;

  UPDATE public.sell_in_orders
  SET
    status = 'finalized',
    finalized_at = NOW(),
    finalized_by = p_sator_id,
    notes = COALESCE(p_notes, notes)
  WHERE id = p_order_id;

  INSERT INTO public.sell_in_order_status_history (
    order_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) VALUES (
    p_order_id,
    'pending',
    'finalized',
    'Finalized by finalize_sell_in_order_by_id',
    p_sator_id
  );

  INSERT INTO public.sales_sell_in (
    sator_id,
    store_id,
    group_id,
    source_order_id,
    variant_id,
    transaction_date,
    qty,
    total_value,
    notes
  )
  SELECT
    v_order.sator_id,
    v_order.store_id,
    v_order.group_id,
    v_order.id,
    i.variant_id,
    v_order.order_date,
    i.qty,
    i.subtotal,
    CONCAT('Finalized order #', v_order.id::TEXT, ' (', v_order.source, ')')
  FROM public.sell_in_order_items i
  WHERE i.order_id = v_order.id
  ON CONFLICT (source_order_id, variant_id)
    WHERE deleted_at IS NULL AND source_order_id IS NOT NULL
  DO NOTHING;

  RETURN json_build_object(
    'success', true,
    'order_id', v_order.id,
    'status', 'finalized',
    'finalized_at', NOW(),
    'total_items', v_order.total_items,
    'total_qty', v_order.total_qty,
    'total_value', v_order.total_value
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_sell_in_order(UUID,UUID,DATE,TEXT,TEXT,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_sell_in_order_by_id(UUID,UUID,TEXT) TO authenticated;
