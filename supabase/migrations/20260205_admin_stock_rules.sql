-- ==========================================================
-- ADMIN STOCK RULES MANAGEMENT (MIN ONLY)
-- Created: 2026-02-05
-- ==========================================================

-- 1. Helper Function: Get All Products with Rules for a specific Grade
DROP FUNCTION IF EXISTS get_products_with_rules(TEXT);

CREATE OR REPLACE FUNCTION get_products_with_rules(p_grade TEXT)
RETURNS TABLE (
  product_id UUID,
  model_name TEXT,
  series TEXT,
  network_type TEXT,
  ram_rom_info TEXT,
  min_qty INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as product_id,
    p.model_name,
    p.series,
    p.network_type,
    (
      SELECT string_agg(DISTINCT pv.ram_rom, ', ') 
      FROM product_variants pv 
      WHERE pv.product_id = p.id
    ) as ram_rom_info,
    COALESCE(sr.min_qty, 0) as min_qty
  FROM products p
  LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = p_grade
  WHERE p.status = 'active'
  ORDER BY p.model_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Helper Function: Update Stock Rule (Min Only)
DROP FUNCTION IF EXISTS update_stock_rule(TEXT, UUID, INTEGER);

CREATE OR REPLACE FUNCTION update_stock_rule(
  p_grade TEXT, 
  p_product_id UUID, 
  p_min INTEGER
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO stock_rules (grade, product_id, min_qty, created_at)
  VALUES (p_grade, p_product_id, p_min, NOW())
  ON CONFLICT (grade, product_id) 
  DO UPDATE SET 
    min_qty = EXCLUDED.min_qty,
    created_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permission
GRANT EXECUTE ON FUNCTION get_products_with_rules(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_stock_rule(TEXT, UUID, INTEGER) TO authenticated;
