DROP FUNCTION IF EXISTS public.get_store_recommendations(UUID);

CREATE OR REPLACE FUNCTION public.get_store_recommendations(p_store_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path TO public
AS $$
  WITH business_day AS (
    SELECT (NOW() AT TIME ZONE 'Asia/Makassar')::DATE AS report_date
  ),
  store_ctx AS (
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
      COALESCE(wsd.quantity, 0) AS warehouse_stock
    FROM public.products p
    JOIN public.product_variants pv
      ON pv.product_id = p.id
     AND pv.active = true
    CROSS JOIN store_ctx sc
    CROSS JOIN business_day bd
    LEFT JOIN public.store_inventory si
      ON si.variant_id = pv.id
     AND si.store_id = p_store_id
    LEFT JOIN public.stock_rules sr
      ON sr.product_id = p.id
     AND sr.grade = sc.grade
    LEFT JOIN public.warehouse_stock_daily wsd
      ON wsd.variant_id = pv.id
     AND wsd.report_date = bd.report_date
     AND LOWER(TRIM(COALESCE(wsd.area, wsd.warehouse_code, ''))) = LOWER(TRIM(sc.area))
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
    '[]'::JSON
  )
  FROM variant_base vb;
$$;

GRANT EXECUTE ON FUNCTION public.get_store_recommendations(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.get_group_store_recommendations(UUID);

CREATE OR REPLACE FUNCTION public.get_group_store_recommendations(
  p_group_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path TO public
AS $$
  WITH business_day AS (
    SELECT (NOW() AT TIME ZONE 'Asia/Makassar')::DATE AS report_date
  ),
  group_ctx AS (
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
      COALESCE(wsd.quantity, 0) AS warehouse_stock,
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
    CROSS JOIN business_day bd
    LEFT JOIN public.warehouse_stock_daily wsd
      ON wsd.variant_id = v.variant_id
     AND wsd.report_date = bd.report_date
     AND LOWER(TRIM(COALESCE(wsd.area, wsd.warehouse_code, ''))) =
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
      wsd.quantity
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
    '[]'::JSON
  )
  FROM variant_base vb
  CROSS JOIN group_ctx gc;
$$;

GRANT EXECUTE ON FUNCTION public.get_group_store_recommendations(UUID) TO authenticated;
