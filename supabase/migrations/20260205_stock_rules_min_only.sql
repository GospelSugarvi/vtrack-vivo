-- ==========================================================
-- ADMIN STOCK RULES (MIN ONLY) - FIXED
-- ==========================================================

-- 1. Function: Get Products with Rules (sudah ok)

-- 2. Function: Update Stock Rule - TERIMA TEXT, KONVERSI KE UUID
DROP FUNCTION IF EXISTS update_stock_rule(TEXT, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION update_stock_rule(
  p_grade TEXT, 
  p_product_id TEXT, 
  p_min INTEGER
)
RETURNS VOID AS $$
DECLARE
  v_product_id UUID;
BEGIN
  -- Convert string to UUID
  v_product_id := p_product_id::UUID;
  
  INSERT INTO stock_rules (grade, product_id, min_qty, created_at)
  VALUES (p_grade, v_product_id, p_min, NOW())
  ON CONFLICT (grade, product_id) 
  DO UPDATE SET 
    min_qty = EXCLUDED.min_qty,
    created_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permission
GRANT EXECUTE ON FUNCTION update_stock_rule(TEXT, TEXT, INTEGER) TO authenticated;
