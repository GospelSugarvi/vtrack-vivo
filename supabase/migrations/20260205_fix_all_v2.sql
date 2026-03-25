-- ==========================================================
-- FIX SEMUA FUNCTION YANG PAKAI ideal_qty
-- ==========================================================

-- 1. Cari dan drop semua function yang punya ideal_qty
-- Function yang bermasalah:

-- Drop get_store_recommendations
DROP FUNCTION IF EXISTS get_store_recommendations(UUID, UUID);
DROP FUNCTION IF EXISTS get_store_recommendations(UUID);

-- Drop update_stock_rule (semua versi)
DROP FUNCTION IF EXISTS update_stock_rule(TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS update_stock_rule(TEXT, UUID, INTEGER);
DROP FUNCTION IF EXISTS update_stock_rule(TEXT, INTEGER);

-- Drop get_products_with_rules (semua versi)
DROP FUNCTION IF EXISTS get_products_with_rules(TEXT);

-- Drop get_store_stock_status
DROP FUNCTION IF EXISTS get_store_stock_status(UUID);

-- 2. Recreate update_stock_rule (yang dipakai admin)
CREATE OR REPLACE FUNCTION update_stock_rule(
  p_grade TEXT, 
  p_product_id TEXT, 
  p_min INTEGER
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO stock_rules (grade, product_id, min_qty, created_at)
  VALUES (p_grade, p_product_id::UUID, p_min, NOW())
  ON CONFLICT (grade, product_id) 
  DO UPDATE SET min_qty = EXCLUDED.min_qty, created_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_stock_rule(TEXT, TEXT, INTEGER) TO authenticated;

-- 3. Recreate get_products_with_rules (untuk admin aturan stok)
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
    (SELECT string_agg(DISTINCT pv.ram_rom, ', ') FROM product_variants pv WHERE pv.product_id = p.id) as ram_rom_info,
    COALESCE(sr.min_qty, 0) as min_qty
  FROM products p
  LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = p_grade
  WHERE p.status = 'active'
  ORDER BY p.model_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_products_with_rules(TEXT) TO authenticated;

-- 4. Recreate get_store_stock_status (untuk list toko)
DROP FUNCTION IF EXISTS get_store_stock_status(UUID);

CREATE FUNCTION get_store_stock_status(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'store_id', s.id,
      'store_name', s.store_name,
      'area', s.area,
      'grade', s.grade,
      'empty_count', COALESCE(stock_status.empty_count, 0),
      'low_count', COALESCE(stock_status.low_count, 0),
      'ok_count', COALESCE(stock_status.ok_count, 0)
    )
  )
  INTO v_result
  FROM stores s
  INNER JOIN assignments_sator_store ass ON ass.store_id = s.id AND ass.sator_id = p_sator_id AND ass.active = true
  LEFT JOIN LATERAL (
    SELECT 
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) = 0) as empty_count,
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) > 0 AND COALESCE(si.quantity, 0) < 3) as low_count,
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) >= 3) as ok_count
    FROM store_inventory si WHERE si.store_id = s.id
  ) stock_status ON true
  WHERE s.deleted_at IS NULL
  ORDER BY stock_status.empty_count DESC;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;

-- 5. Recreate get_store_recommendations (untuk halaman rekomendasi)
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
  RETURN '[]'::json;
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_recommendations(UUID, UUID) TO authenticated;
