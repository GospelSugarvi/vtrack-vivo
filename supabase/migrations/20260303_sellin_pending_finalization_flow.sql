-- Sell In Pending -> Finalization Flow
-- Date: 2026-03-03

-- 1) Save draft order (pending)
DROP FUNCTION IF EXISTS public.save_sell_in_order_draft(UUID,UUID,DATE,TEXT,TEXT,JSONB);
CREATE OR REPLACE FUNCTION public.save_sell_in_order_draft(
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
BEGIN
  IF p_sator_id IS NULL OR p_store_id IS NULL THEN
    RAISE EXCEPTION 'p_sator_id and p_store_id are required';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items must be a JSON array';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_sator_id THEN
    RAISE EXCEPTION 'Unauthorized draft context';
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
    RAISE EXCEPTION 'No valid order items to save';
  END IF;

  INSERT INTO public.sell_in_orders (
    sator_id,
    store_id,
    order_date,
    source,
    status,
    notes,
    total_items,
    total_qty,
    total_value
  ) VALUES (
    p_sator_id,
    p_store_id,
    COALESCE(p_order_date, CURRENT_DATE),
    p_source,
    'pending',
    p_notes,
    v_total_items,
    v_total_qty,
    v_total_value
  )
  RETURNING id INTO v_order_id;

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

  SELECT st.store_name INTO v_store_name
  FROM public.stores st
  WHERE st.id = p_store_id;

  RETURN json_build_object(
    'success', true,
    'order_id', v_order_id,
    'store_id', p_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'order_date', COALESCE(p_order_date, CURRENT_DATE),
    'source', p_source,
    'status', 'pending',
    'total_items', v_total_items,
    'total_qty', v_total_qty,
    'total_value', v_total_value,
    'created_at', NOW()
  );
END;
$$;

-- 2) Pending order detail for finalization page
DROP FUNCTION IF EXISTS public.get_sell_in_order_detail(UUID,UUID);
CREATE OR REPLACE FUNCTION public.get_sell_in_order_detail(
  p_sator_id UUID,
  p_order_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'order', json_build_object(
      'id', o.id,
      'sator_id', o.sator_id,
      'store_id', o.store_id,
      'store_name', st.store_name,
      'order_date', o.order_date,
      'source', o.source,
      'status', o.status,
      'notes', o.notes,
      'total_items', o.total_items,
      'total_qty', o.total_qty,
      'total_value', o.total_value,
      'created_at', o.created_at,
      'finalized_at', o.finalized_at
    ),
    'items', COALESCE(
      (
        SELECT json_agg(
          json_build_object(
            'variant_id', i.variant_id,
            'qty', i.qty,
            'price', i.price,
            'subtotal', i.subtotal,
            'product_name', p.model_name,
            'variant', pv.ram_rom,
            'color', pv.color,
            'network_type', p.network_type
          ) ORDER BY p.model_name, pv.ram_rom, pv.color
        )
        FROM public.sell_in_order_items i
        JOIN public.product_variants pv ON pv.id = i.variant_id
        JOIN public.products p ON p.id = pv.product_id
        WHERE i.order_id = o.id
      ),
      '[]'::json
    )
  )
  FROM public.sell_in_orders o
  JOIN public.stores st ON st.id = o.store_id
  WHERE o.id = p_order_id
    AND o.sator_id = p_sator_id;
$$;

-- 3) Finalize by pending order id (single controlled stage)
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

  -- feed existing sell_in pipeline
  INSERT INTO public.sales_sell_in (
    sator_id,
    store_id,
    variant_id,
    transaction_date,
    qty,
    total_value,
    notes
  )
  SELECT
    v_order.sator_id,
    v_order.store_id,
    i.variant_id,
    v_order.order_date,
    i.qty,
    i.subtotal,
    CONCAT('Finalized order #', v_order.id::TEXT, ' (', v_order.source, ')')
  FROM public.sell_in_order_items i
  WHERE i.order_id = v_order.id;

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

-- 4) Richer pending list for UI
DROP FUNCTION IF EXISTS public.get_pending_orders(UUID);
CREATE OR REPLACE FUNCTION public.get_pending_orders(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', o.id,
      'store_id', o.store_id,
      'store_name', st.store_name,
      'order_date', o.order_date,
      'source', o.source,
      'total_items', o.total_items,
      'total_qty', o.total_qty,
      'total_value', o.total_value,
      'status', o.status,
      'created_at', o.created_at
    ) ORDER BY o.created_at DESC
  ), '[]'::json)
  FROM public.sell_in_orders o
  JOIN public.stores st ON st.id = o.store_id
  WHERE o.sator_id = p_sator_id
    AND o.status = 'pending';
$$;

GRANT EXECUTE ON FUNCTION public.save_sell_in_order_draft(UUID,UUID,DATE,TEXT,TEXT,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sell_in_order_detail(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_sell_in_order_by_id(UUID,UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_orders(UUID) TO authenticated;
