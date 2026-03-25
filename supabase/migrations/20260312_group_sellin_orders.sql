-- Group Sell-In Orders (Per Grup Toko)
-- Date: 2026-03-12

-- 1) Add group_id to sell_in_orders and sales_sell_in
ALTER TABLE public.sell_in_orders
ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.store_groups(id);

CREATE INDEX IF NOT EXISTS idx_sell_in_orders_group_id
  ON public.sell_in_orders(group_id);

ALTER TABLE public.sales_sell_in
ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.store_groups(id);

CREATE INDEX IF NOT EXISTS idx_sales_sell_in_group_id
  ON public.sales_sell_in(group_id);

-- 2) Update get_store_stock_status to include group info
DROP FUNCTION IF EXISTS public.get_store_stock_status(UUID);
CREATE OR REPLACE FUNCTION public.get_store_stock_status(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  store_ids AS (
    SELECT DISTINCT store_id
    FROM assignments_promotor_store
    WHERE promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', st.id,
      'store_name', st.store_name,
      'group_id', st.group_id,
      'group_name', sg.group_name,
      'empty_count', (
        SELECT COUNT(*) FROM store_inventory si
        WHERE si.store_id = st.id AND si.quantity = 0
      ),
      'low_count', (
        SELECT COUNT(*) FROM store_inventory si
        WHERE si.store_id = st.id AND si.quantity > 0 AND si.quantity < 3
      )
    )
  ), '[]'::json)
  FROM stores st
  LEFT JOIN store_groups sg ON sg.id = st.group_id
  WHERE st.id IN (SELECT store_id FROM store_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_store_stock_status(UUID) TO authenticated;

-- 3) Update get_reorder_recommendations to include group info
DROP FUNCTION IF EXISTS public.get_reorder_recommendations(UUID, UUID);
CREATE OR REPLACE FUNCTION public.get_reorder_recommendations(
  p_sator_id UUID,
  p_store_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  WITH store_info AS (
    SELECT DISTINCT
      aps.store_id,
      s.grade as store_grade,
      s.store_name,
      s.group_id,
      sg.group_name
    FROM assignments_promotor_store aps
    JOIN stores s ON s.id = aps.store_id
    LEFT JOIN store_groups sg ON sg.id = s.group_id
    WHERE aps.promotor_id IN (
      SELECT promotor_id
      FROM hierarchy_sator_promotor
      WHERE sator_id = p_sator_id AND active = true
    )
    AND aps.active = true
    AND (p_store_id IS NULL OR aps.store_id = p_store_id)
  ),
  stock_calc AS (
    SELECT
      si.store_id,
      p.id as product_id,
      pv.id as variant_id,
      p.model_name,
      pv.ram_rom,
      pv.color,
      pv.srp as price,
      p.network_type,
      p.series,
      COALESCE(SUM(CASE WHEN st.is_sold = false THEN 1 ELSE 0 END), 0) as current_stock,
      si.store_grade,
      si.store_name,
      si.group_id,
      si.group_name,
      COALESCE(sr.min_qty, 3) as min_stock
    FROM store_info si
    CROSS JOIN products p
    JOIN product_variants pv ON pv.product_id = p.id AND pv.active = true
    LEFT JOIN stok st ON st.variant_id = pv.id AND st.store_id = si.store_id
    LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = si.store_grade
    WHERE p.status = 'active'
    GROUP BY si.store_id, p.id, pv.id, p.model_name, pv.ram_rom, pv.color, pv.srp, p.network_type, p.series, si.store_grade, si.store_name, si.group_id, si.group_name, sr.min_qty
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', sc.store_id,
      'store_name', sc.store_name,
      'store_grade', sc.store_grade,
      'group_id', sc.group_id,
      'group_name', sc.group_name,
      'product_id', sc.product_id,
      'variant_id', sc.variant_id,
      'product_name', sc.model_name,
      'variant', sc.ram_rom,
      'color', sc.color,
      'price', sc.price,
      'network_type', sc.network_type,
      'series', sc.series,
      'current_stock', sc.current_stock,
      'min_stock', sc.min_stock,
      'reorder_qty', GREATEST(sc.min_stock - sc.current_stock, 0),
      'status', CASE
        WHEN sc.current_stock = 0 THEN 'HABIS'
        WHEN sc.current_stock < sc.min_stock THEN 'KURANG'
        ELSE 'CUKUP'
      END
    )
    ORDER BY
      CASE WHEN sc.current_stock = 0 THEN 1
           WHEN sc.current_stock < sc.min_stock THEN 2 ELSE 3 END,
      sc.model_name
  ), '[]'::json)
  INTO v_result
  FROM stock_calc sc
  WHERE sc.current_stock < sc.min_stock;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_reorder_recommendations(UUID, UUID) TO authenticated;

-- 4) Update save_sell_in_order_draft to set group_id
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
  v_group_id UUID;
  v_group_name TEXT;
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

  SELECT st.store_name, st.group_id, sg.group_name
  INTO v_store_name, v_group_id, v_group_name
  FROM public.stores st
  LEFT JOIN public.store_groups sg ON sg.id = st.group_id
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
    total_value
  ) VALUES (
    p_sator_id,
    p_store_id,
    v_group_id,
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

  RETURN json_build_object(
    'success', true,
    'order_id', v_order_id,
    'store_id', p_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'group_id', v_group_id,
    'group_name', COALESCE(v_group_name, ''),
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

GRANT EXECUTE ON FUNCTION public.save_sell_in_order_draft(UUID,UUID,DATE,TEXT,TEXT,JSONB) TO authenticated;

-- 5) Update get_sell_in_order_detail to include group info
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
      'group_id', o.group_id,
      'group_name', sg.group_name,
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
  LEFT JOIN public.store_groups sg ON sg.id = o.group_id
  WHERE o.id = p_order_id
    AND o.sator_id = p_sator_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_sell_in_order_detail(UUID,UUID) TO authenticated;

-- 6) Update finalize_sell_in_order_by_id to persist group_id to sales_sell_in
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
    group_id,
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

GRANT EXECUTE ON FUNCTION public.finalize_sell_in_order_by_id(UUID,UUID,TEXT) TO authenticated;

-- 7) Update get_pending_orders to include group info
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
      'group_id', o.group_id,
      'group_name', sg.group_name,
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
  LEFT JOIN public.store_groups sg ON sg.id = o.group_id
  WHERE o.sator_id = p_sator_id
    AND o.status = 'pending';
$$;

GRANT EXECUTE ON FUNCTION public.get_pending_orders(UUID) TO authenticated;
