-- ==========================================================
-- FIX LENGKAP: get_store_recommendations (tanpa ideal_qty)
-- ==========================================================

DROP FUNCTION IF EXISTS get_store_recommendations(UUID, UUID);

CREATE OR REPLACE FUNCTION get_store_recommendations(
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
  -- Get products that need reorder based on min_qty from stock_rules
  WITH store_stocks AS (
    SELECT 
      s.id as store_id,
      s.store_name,
      s.grade,
      pv.id as variant_id,
      pv.product_id,
      p.model_name,
      pv.ram_rom,
      pv.color,
      pv.srp as price,
      COALESCE(si.quantity, 0) as current_stock,
      COALESCE(sr.min_qty, 3) as min_stock
    FROM stores s
    INNER JOIN assignments_sator_store ass ON ass.store_id = s.id AND ass.sator_id = p_sator_id AND ass.active = true
    CROSS JOIN product_variants pv
    JOIN products p ON p.id = pv.product_id AND p.status = 'active'
    LEFT JOIN store_inventory si ON si.store_id = s.id AND si.variant_id = pv.id
    LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = s.grade
    WHERE s.deleted_at IS NULL
    AND (p_store_id IS NULL OR s.id = p_store_id)
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', store_id,
      'store_name', store_name,
      'product_id', product_id,
      'variant_id', variant_id,
      'product_name', model_name,
      'variant', ram_rom,
      'color', color,
      'price', price,
      'current_stock', current_stock,
      'min_stock', min_stock,
      'reorder_qty', GREATEST(min_stock - current_stock, 0),
      'status', CASE 
        WHEN current_stock = 0 THEN 'HABIS'
        WHEN current_stock < min_stock THEN 'KURANG'
        ELSE 'CUKUP'
      END
    )
    ORDER BY 
      CASE WHEN current_stock = 0 THEN 1 
           WHEN current_stock < min_stock THEN 2 ELSE 3 END,
      model_name
  ), '[]'::json)
  INTO v_result
  FROM store_stocks
  WHERE current_stock < min_stock;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_recommendations(UUID, UUID) TO authenticated;
