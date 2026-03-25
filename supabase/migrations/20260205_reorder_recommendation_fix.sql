-- ==========================================================
-- GET REORDER RECOMMENDATIONS (PAKAI MIN STOCK)
-- Menambahkan: stok_toko, min_stock, status
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
  -- Get all products with their stock rules
  WITH store_info AS (
    -- Get stores under this sator
    SELECT DISTINCT 
      aps.store_id,
      s.grade,
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
    -- Calculate current stock per store per product
    SELECT 
      si.store_id,
      p.id as product_id,
      pv.id as variant_id,
      p.model_name,
      pv.ram_rom,
      pv.color,
      pv.srp as price,
      COALESCE(SUM(CASE WHEN si.is_sold = false THEN 1 ELSE 0 END), 0) as current_stock
    FROM store_info si
    CROSS JOIN products p
    JOIN product_variants pv ON pv.product_id = p.id
    LEFT JOIN stok si2 ON si2.variant_id = pv.id AND si2.store_id = si.store_id AND si2.is_sold = false
    WHERE p.status = 'active' AND pv.active = true
    GROUP BY si.store_id, p.id, pv.id, p.model_name, pv.ram_rom, pv.color, pv.srp
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', sc.store_id,
      'store_name', (SELECT store_name FROM store_info WHERE store_id = sc.store_id LIMIT 1),
      'product_id', sc.product_id,
      'variant_id', sc.variant_id,
      'product_name', sc.model_name,
      'variant', sc.ram_rom,
      'color', sc.color,
      'price', sc.price,
      'current_stock', sc.current_stock,
      'min_stock', COALESCE(
        (SELECT min_qty FROM stock_rules WHERE grade = (SELECT grade FROM store_info WHERE store_id = sc.store_id LIMIT 1) AND product_id = sc.product_id),
        3 -- Default min = 3 kalau tidak ada rule
      ),
      'reorder_qty', GREATEST(
        COALESCE(
          (SELECT min_qty FROM stock_rules WHERE grade = (SELECT grade FROM store_info WHERE store_id = sc.store_id LIMIT 1) AND product_id = sc.product_id),
          3
        ) - sc.current_stock,
        0
      ),
      'status', CASE 
        WHEN sc.current_stock = 0 THEN 'HABIS'
        WHEN sc.current_stock < COALESCE(
          (SELECT min_qty FROM stock_rules WHERE grade = (SELECT grade FROM store_info WHERE store_id = sc.store_id LIMIT 1) AND product_id = sc.product_id),
          3
        ) THEN 'KURANG'
        ELSE 'CUKUP'
      END
    )
    ORDER BY 
      CASE 
        WHEN sc.current_stock = 0 THEN 1
        WHEN sc.current_stock < COALESCE(
          (SELECT min_qty FROM stock_rules WHERE grade = (SELECT grade FROM store_info WHERE store_id = sc.store_id LIMIT 1) AND product_id = sc.product_id),
          3
        ) THEN 2
        ELSE 3
      END,
      sc.model_name
  ), '[]'::json)
  INTO v_result
  FROM stock_calc sc
  WHERE sc.current_stock < COALESCE(
    (SELECT min_qty FROM stock_rules WHERE grade = (SELECT grade FROM store_info WHERE store_id = sc.store_id LIMIT 1) AND product_id = sc.product_id),
    3
  );

  RETURN v_result;
END;
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION get_reorder_recommendations(UUID, UUID) TO authenticated;
