-- Align store recommendation with warehouse stock + store stock + grade min stock

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
