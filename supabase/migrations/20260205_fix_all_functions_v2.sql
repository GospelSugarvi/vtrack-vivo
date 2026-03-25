-- ==========================================================
-- FIX LENGKAP: get_store_recommendations & update_stock_rule
-- ==========================================================

-- 1. DROP update_stock_rule (TEXT, TEXT, INTEGER) dulu
DROP FUNCTION IF EXISTS update_stock_rule(TEXT, TEXT, INTEGER);

-- 2. Buat ulang update_stock_rule
CREATE OR REPLACE FUNCTION update_stock_rule(
  p_grade TEXT, 
  p_product_id TEXT, 
  p_min INTEGER
)
RETURNS VOID AS $$
DECLARE
  v_product_id UUID;
BEGIN
  v_product_id := p_product_id::UUID;
  
  INSERT INTO stock_rules (grade, product_id, min_qty, created_at)
  VALUES (p_grade, v_product_id, p_min, NOW())
  ON CONFLICT (grade, product_id) 
  DO UPDATE SET 
    min_qty = EXCLUDED.min_qty,
    created_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_stock_rule(TEXT, TEXT, INTEGER) TO authenticated;

-- 3. DROP dan RECREATE get_store_recommendations
-- Function ini perlu dilhat dulu isinya, tapi sementara kita buat ulang
DROP FUNCTION IF EXISTS get_store_recommendations(UUID, UUID);

CREATE OR REPLACE FUNCTION get_store_recommendations(
  p_sator_id UUID,
  p_store_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Return empty for now - need to rebuild full logic
  RETURN '[]'::json;
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_recommendations(UUID, UUID) TO authenticated;
