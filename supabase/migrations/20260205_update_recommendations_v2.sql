-- ==========================================================
-- UPDATE get_reorder_recommendations - Include store_grade
-- ==========================================================

DROP FUNCTION IF EXISTS get_reorder_recommendations(UUID, UUID);

CREATE OR REPLACE FUNCTION get_reorder_recommendations(
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
      s.store_name
    FROM assignments_promotor_store aps
    JOIN stores s ON s.id = aps.store_id
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
      COALESCE(sr.min_qty, 3) as min_stock
    FROM store_info si
    CROSS JOIN products p
    JOIN product_variants pv ON pv.product_id = p.id AND pv.active = true
    LEFT JOIN stok st ON st.variant_id = pv.id AND st.store_id = si.store_id
    LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = si.store_grade
    WHERE p.status = 'active'
    GROUP BY si.store_id, p.id, pv.id, p.model_name, pv.ram_rom, pv.color, pv.srp, p.network_type, p.series, si.store_grade, si.store_name, sr.min_qty
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', sc.store_id,
      'store_name', sc.store_name,
      'store_grade', sc.store_grade,
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

GRANT EXECUTE ON FUNCTION get_reorder_recommendations(UUID, UUID) TO authenticated;
