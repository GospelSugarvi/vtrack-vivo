-- Server-driven sell-in preview totals and modal-based draft pricing

DROP FUNCTION IF EXISTS public.get_store_recommendations(UUID);

CREATE OR REPLACE FUNCTION public.get_store_recommendations(p_store_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH store_ctx AS (
    SELECT
      s.id,
      COALESCE(NULLIF(TRIM(s.area), ''), 'Gudang') AS area,
      s.grade
    FROM public.stores s
    WHERE s.id = p_store_id
    LIMIT 1
  ),
  variant_base AS (
    SELECT
      pv.id AS variant_id,
      p.id AS product_id,
      p.model_name AS product_name,
      p.network_type,
      p.series,
      pv.ram_rom AS variant,
      pv.color,
      pv.srp AS price,
      COALESCE(pv.modal, 0) AS modal,
      COALESCE(si.quantity, 0) AS current_stock,
      COALESCE(sr.min_qty, 3) AS min_stock,
      GREATEST(COALESCE(sr.min_qty, 3) - COALESCE(si.quantity, 0), 0) AS shortage_qty,
      COALESCE(ws.quantity, 0) AS warehouse_stock
    FROM public.products p
    JOIN public.product_variants pv
      ON pv.product_id = p.id
     AND pv.active = true
    CROSS JOIN store_ctx sc
    LEFT JOIN public.store_inventory si
      ON si.variant_id = pv.id
     AND si.store_id = p_store_id
    LEFT JOIN public.stock_rules sr
      ON sr.product_id = p.id
     AND sr.grade = sc.grade
    LEFT JOIN public.warehouse_stock ws
      ON ws.variant_id = pv.id
     AND LOWER(TRIM(COALESCE(ws.area, ws.warehouse_code, ''))) = LOWER(TRIM(sc.area))
    WHERE p.status = 'active'
  )
  SELECT COALESCE(
    json_agg(
      json_build_object(
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
  FROM variant_base vb;
$$;

GRANT EXECUTE ON FUNCTION public.get_store_recommendations(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sell_in_order_preview(UUID, JSONB);

CREATE OR REPLACE FUNCTION public.get_sell_in_order_preview(
  p_store_id UUID,
  p_items JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store_name TEXT;
  v_total_items INTEGER := 0;
  v_total_qty INTEGER := 0;
  v_total_value NUMERIC := 0;
  v_items JSON := '[]'::json;
BEGIN
  IF p_store_id IS NULL THEN
    RAISE EXCEPTION 'p_store_id is required';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items must be a JSON array';
  END IF;

  SELECT st.store_name
  INTO v_store_name
  FROM public.stores st
  WHERE st.id = p_store_id;

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
    'store_id', p_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'total_items', v_total_items,
    'total_qty', v_total_qty,
    'total_value', v_total_value,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sell_in_order_preview(UUID, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sell_in_finalization_summary(UUID);

CREATE OR REPLACE FUNCTION public.get_sell_in_finalization_summary(
  p_sator_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'pending_order_count', COUNT(*) FILTER (WHERE o.status = 'pending'),
    'pending_total_items', COALESCE(SUM(o.total_items) FILTER (WHERE o.status = 'pending'), 0),
    'pending_total_qty', COALESCE(SUM(o.total_qty) FILTER (WHERE o.status = 'pending'), 0),
    'pending_total_value', COALESCE(SUM(o.total_value) FILTER (WHERE o.status = 'pending'), 0),
    'finalized_order_count', COUNT(*) FILTER (WHERE o.status = 'finalized'),
    'finalized_total_items', COALESCE(SUM(o.total_items) FILTER (WHERE o.status = 'finalized'), 0),
    'finalized_total_qty', COALESCE(SUM(o.total_qty) FILTER (WHERE o.status = 'finalized'), 0),
    'finalized_total_value', COALESCE(SUM(o.total_value) FILTER (WHERE o.status = 'finalized'), 0)
  )
  FROM public.sell_in_orders o
  WHERE o.sator_id = p_sator_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_sell_in_finalization_summary(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sellin_dashboard_snapshot(UUID);

CREATE OR REPLACE FUNCTION public.get_sellin_dashboard_snapshot(
  p_sator_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH gudang_rows AS (
    SELECT *
    FROM json_to_recordset(COALESCE(public.get_gudang_stock(p_sator_id), '[]'::json)) AS x(
      product_id uuid,
      product_name text,
      variant text,
      color text,
      price numeric,
      qty integer,
      category text
    )
  ),
  gudang_summary AS (
    SELECT json_build_object(
      'banyak', COUNT(*) FILTER (WHERE COALESCE(qty, 0) > 9),
      'cukup', COUNT(*) FILTER (WHERE COALESCE(qty, 0) BETWEEN 4 AND 9),
      'kritis', COUNT(*) FILTER (WHERE COALESCE(qty, 0) BETWEEN 1 AND 3),
      'kosong', COUNT(*) FILTER (WHERE COALESCE(qty, 0) <= 0),
      'top_rows', COALESCE(
        (
          SELECT json_agg(
            json_build_object(
              'product_name', gr.product_name,
              'variant', gr.variant,
              'qty', gr.qty,
              'category', gr.category
            )
            ORDER BY gr.qty ASC, gr.price ASC, gr.product_name, gr.variant
          )
          FROM (
            SELECT *
            FROM gudang_rows
            ORDER BY qty ASC, price ASC, product_name, variant
            LIMIT 3
          ) gr
        ),
        '[]'::json
      )
    ) AS payload
    FROM gudang_rows
  ),
  store_rows AS (
    SELECT *
    FROM json_to_recordset(COALESCE(public.get_store_stock_status(p_sator_id), '[]'::json)) AS x(
      store_id uuid,
      store_name text,
      group_id uuid,
      group_name text,
      empty_count integer,
      low_count integer
    )
  ),
  store_summary AS (
    SELECT COALESCE(
      json_agg(
        json_build_object(
          'store_id', s.store_id,
          'store_name', s.store_name,
          'group_id', s.group_id,
          'group_name', s.group_name,
          'empty_count', s.empty_count,
          'low_count', s.low_count
        )
        ORDER BY COALESCE(s.empty_count, 0) DESC, COALESCE(s.low_count, 0) DESC, s.store_name
      ),
      '[]'::json
    ) AS payload
    FROM (
      SELECT *
      FROM store_rows
      ORDER BY COALESCE(empty_count, 0) DESC, COALESCE(low_count, 0) DESC, store_name
      LIMIT 4
    ) s
  ),
  pending_summary AS (
    SELECT COALESCE(
      json_agg(
        json_build_object(
          'id', o.id,
          'store_name', o.store_name,
          'group_name', o.group_name,
          'total_items', o.total_items,
          'total_qty', o.total_qty,
          'total_value', o.total_value,
          'order_date', o.order_date,
          'source', o.source,
          'status', o.status
        )
        ORDER BY o.order_date DESC, o.id DESC
      ),
      '[]'::json
    ) AS payload
    FROM (
      SELECT *
      FROM json_to_recordset(COALESCE(public.get_pending_orders(p_sator_id), '[]'::json)) AS x(
        id uuid,
        store_name text,
        group_name text,
        total_items integer,
        total_qty integer,
        total_value numeric,
        order_date date,
        source text,
        status text
      )
      ORDER BY order_date DESC, id DESC
      LIMIT 4
    ) o
  )
  SELECT json_build_object(
    'gudang', COALESCE((SELECT payload FROM gudang_summary), '{}'::json),
    'stores', COALESCE((SELECT payload FROM store_summary), '[]'::json),
    'pending_orders', COALESCE((SELECT payload FROM pending_summary), '[]'::json)
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_sellin_dashboard_snapshot(UUID) TO authenticated;

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
