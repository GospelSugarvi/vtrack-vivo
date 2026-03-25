-- ==========================================================
-- FIX ALL: Hapus kolom ideal_qty dari semua function
-- ==========================================================

-- 1. Cari dan drop function yang punya ideal_qty
DROP FUNCTION IF EXISTS get_store_stock_status(uuid);
DROP FUNCTION IF EXISTS get_products_with_rules(text);

-- 2. Recreate get_store_stock_status (tanpa ideal_qty)
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
  INNER JOIN assignments_sator_store ass 
    ON ass.store_id = s.id 
    AND ass.sator_id = p_sator_id 
    AND ass.active = true
  LEFT JOIN LATERAL (
    SELECT 
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) = 0) as empty_count,
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) > 0 AND COALESCE(si.quantity, 0) < 3) as low_count,
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) >= 3) as ok_count
    FROM store_inventory si
    WHERE si.store_id = s.id
  ) stock_status ON true
  WHERE s.deleted_at IS NULL
  ORDER BY stock_status.empty_count DESC;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;

-- 3. Recreate get_products_with_rules (tanpa ideal_qty)
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

GRANT EXECUTE ON FUNCTION get_products_with_rules(TEXT) TO authenticated;
