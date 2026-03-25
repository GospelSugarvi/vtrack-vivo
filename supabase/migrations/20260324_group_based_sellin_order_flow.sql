-- Group-based sell-in recommendation / preview / draft flow

DROP FUNCTION IF EXISTS public.get_group_store_recommendations(UUID);

CREATE OR REPLACE FUNCTION public.get_group_store_recommendations(
  p_group_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH group_ctx AS (
    SELECT
      sg.id AS group_id,
      sg.group_name,
      rep.id AS representative_store_id,
      COALESCE(NULLIF(TRIM(rep.area), ''), 'Gudang') AS area
    FROM public.store_groups sg
    JOIN LATERAL (
      SELECT s.id, s.area
      FROM public.stores s
      WHERE s.group_id = sg.id
      ORDER BY s.store_name, s.id
      LIMIT 1
    ) rep ON TRUE
    WHERE sg.id = p_group_id
  ),
  store_members AS (
    SELECT
      s.id AS store_id,
      s.store_name,
      s.grade
    FROM public.stores s
    WHERE s.group_id = p_group_id
      AND s.deleted_at IS NULL
  ),
  variant_per_store AS (
    SELECT
      sm.store_id,
      sm.store_name,
      pv.id AS variant_id,
      p.id AS product_id,
      p.model_name AS product_name,
      p.network_type,
      p.series,
      pv.ram_rom AS variant,
      pv.color,
      pv.srp AS price,
      COALESCE(pv.modal, 0) AS modal,
      COALESCE(si.quantity, 0) AS current_stock_store,
      COALESCE(sr.min_qty, 3) AS min_stock_store,
      GREATEST(COALESCE(sr.min_qty, 3) - COALESCE(si.quantity, 0), 0) AS shortage_store
    FROM store_members sm
    CROSS JOIN public.products p
    JOIN public.product_variants pv
      ON pv.product_id = p.id
     AND pv.active = TRUE
    LEFT JOIN public.store_inventory si
      ON si.variant_id = pv.id
     AND si.store_id = sm.store_id
    LEFT JOIN public.stock_rules sr
      ON sr.product_id = p.id
     AND sr.grade = sm.grade
    WHERE p.status = 'active'
  ),
  variant_base AS (
    SELECT
      v.variant_id,
      v.product_id,
      v.product_name,
      v.network_type,
      v.series,
      v.variant,
      v.color,
      v.price,
      v.modal,
      COALESCE(SUM(v.current_stock_store), 0) AS current_stock,
      COALESCE(SUM(v.min_stock_store), 0) AS min_stock,
      COALESCE(SUM(v.shortage_store), 0) AS shortage_qty,
      COALESCE(ws.quantity, 0) AS warehouse_stock,
      COUNT(DISTINCT v.store_id) AS total_stores,
      COALESCE(
        json_agg(
          json_build_object(
            'store_id', v.store_id,
            'store_name', v.store_name,
            'current_stock', v.current_stock_store,
            'min_stock', v.min_stock_store,
            'shortage_qty', v.shortage_store
          )
          ORDER BY v.store_name
        ),
        '[]'::json
      ) AS store_breakdown
    FROM variant_per_store v
    CROSS JOIN group_ctx gc
    LEFT JOIN public.warehouse_stock ws
      ON ws.variant_id = v.variant_id
     AND LOWER(TRIM(COALESCE(ws.area, ws.warehouse_code, ''))) =
         LOWER(TRIM(gc.area))
    GROUP BY
      v.variant_id,
      v.product_id,
      v.product_name,
      v.network_type,
      v.series,
      v.variant,
      v.color,
      v.price,
      v.modal,
      ws.quantity
  )
  SELECT COALESCE(
    json_agg(
      json_build_object(
        'group_id', gc.group_id,
        'group_name', gc.group_name,
        'representative_store_id', gc.representative_store_id,
        'variant_id', vb.variant_id,
        'product_id', vb.product_id,
        'product_name', vb.product_name,
        'variant', vb.variant,
        'color', vb.color,
        'price', vb.price,
        'modal', vb.modal,
        'network_type', vb.network_type,
        'series', vb.series,
        'current_stock', vb.current_stock,
        'min_stock', vb.min_stock,
        'shortage_qty', vb.shortage_qty,
        'warehouse_stock', vb.warehouse_stock,
        'available_gudang', vb.warehouse_stock,
        'order_qty', LEAST(vb.shortage_qty, vb.warehouse_stock),
        'unfulfilled_qty', GREATEST(vb.shortage_qty - vb.warehouse_stock, 0),
        'can_fulfill', (vb.shortage_qty > 0 AND vb.warehouse_stock >= vb.shortage_qty),
        'total_stores', vb.total_stores,
        'store_breakdown', vb.store_breakdown,
        'status',
          CASE
            WHEN vb.current_stock = 0 THEN 'HABIS'
            WHEN vb.current_stock < vb.min_stock THEN 'KURANG'
            ELSE 'CUKUP'
          END,
        'recommendation_status',
          CASE
            WHEN vb.shortage_qty <= 0 THEN 'NO_NEED'
            WHEN vb.warehouse_stock <= 0 THEN 'NO_GUDANG'
            WHEN vb.warehouse_stock < vb.shortage_qty THEN 'LIMITED_GUDANG'
            ELSE 'READY_TO_ORDER'
          END
      )
      ORDER BY
        CASE
          WHEN vb.shortage_qty <= 0 THEN 3
          WHEN vb.warehouse_stock <= 0 THEN 2
          WHEN vb.warehouse_stock < vb.shortage_qty THEN 1
          ELSE 0
        END,
        vb.shortage_qty DESC,
        vb.warehouse_stock DESC,
        vb.product_name,
        vb.variant,
        vb.color
    ),
    '[]'::json
  )
  FROM variant_base vb
  CROSS JOIN group_ctx gc;
$$;

GRANT EXECUTE ON FUNCTION public.get_group_store_recommendations(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sell_in_group_order_preview(UUID, JSONB);

CREATE OR REPLACE FUNCTION public.get_sell_in_group_order_preview(
  p_group_id UUID,
  p_items JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_name TEXT;
  v_store_id UUID;
  v_store_name TEXT;
  v_total_items INTEGER := 0;
  v_total_qty INTEGER := 0;
  v_total_value NUMERIC := 0;
  v_items JSON := '[]'::json;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items must be a JSON array';
  END IF;

  SELECT sg.group_name, s.id, s.store_name
  INTO v_group_name, v_store_id, v_store_name
  FROM public.store_groups sg
  JOIN public.stores s ON s.group_id = sg.id
  WHERE sg.id = p_group_id
  ORDER BY s.store_name, s.id
  LIMIT 1;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'No store found for group';
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
      pr.model_name AS product_name,
      pr.network_type,
      pv.ram_rom AS variant,
      pv.color,
      COALESCE(pv.modal, 0)::NUMERIC AS modal,
      COALESCE(pv.srp, 0)::NUMERIC AS price,
      (p.qty * COALESCE(pv.modal, 0)::NUMERIC) AS subtotal
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
    COALESCE(SUM(subtotal), 0)::NUMERIC,
    COALESCE(
      json_agg(
        json_build_object(
          'variant_id', variant_id,
          'qty', qty,
          'product_name', product_name,
          'network_type', network_type,
          'variant', variant,
          'color', color,
          'modal', modal,
          'price', price,
          'subtotal', subtotal
        )
        ORDER BY product_name, network_type, variant, color
      ),
      '[]'::json
    )
  INTO v_total_items, v_total_qty, v_total_value, v_items
  FROM valid;

  RETURN json_build_object(
    'group_id', p_group_id,
    'group_name', COALESCE(v_group_name, ''),
    'store_id', v_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'total_items', v_total_items,
    'total_qty', v_total_qty,
    'total_value', v_total_value,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sell_in_group_order_preview(UUID, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS public.save_sell_in_group_order_draft(UUID,UUID,DATE,TEXT,TEXT,JSONB);

CREATE OR REPLACE FUNCTION public.save_sell_in_group_order_draft(
  p_sator_id UUID,
  p_group_id UUID,
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
  v_store_id UUID;
  v_store_name TEXT;
  v_group_name TEXT;
BEGIN
  IF p_sator_id IS NULL OR p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_sator_id and p_group_id are required';
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

  SELECT s.id, s.store_name, sg.group_name
  INTO v_store_id, v_store_name, v_group_name
  FROM public.store_groups sg
  JOIN public.stores s ON s.group_id = sg.id
  WHERE sg.id = p_group_id
  ORDER BY s.store_name, s.id
  LIMIT 1;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'No representative store found for group';
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
      COALESCE(pv.modal, 0)::NUMERIC AS price,
      (p.qty * COALESCE(pv.modal, 0)::NUMERIC) AS subtotal
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
    v_store_id,
    p_group_id,
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
      COALESCE(pv.modal, 0)::NUMERIC AS price,
      (p.qty * COALESCE(pv.modal, 0)::NUMERIC) AS subtotal
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
    'store_id', v_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'group_id', p_group_id,
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

GRANT EXECUTE ON FUNCTION public.save_sell_in_group_order_draft(UUID,UUID,DATE,TEXT,TEXT,JSONB) TO authenticated;
