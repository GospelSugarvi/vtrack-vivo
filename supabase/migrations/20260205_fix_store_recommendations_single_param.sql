-- ==========================================================
-- BUAT FUNCTION get_store_recommendations dengan 1 parameter
-- Dipanggil dari halaman stok_toko_page.dart
-- ==========================================================

DROP FUNCTION IF EXISTS get_store_recommendations(UUID);

CREATE OR REPLACE FUNCTION get_store_recommendations(p_store_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT COALESCE(json_agg(
    json_build_object(
      'variant_id', pv.id,
      'product_id', p.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'current_stock', COALESCE(si.quantity, 0),
      'min_stock', COALESCE(sr.min_qty, 3),
      'order_qty', GREATEST(COALESCE(sr.min_qty, 3) - COALESCE(si.quantity, 0), 0),
      'status', CASE 
        WHEN COALESCE(si.quantity, 0) = 0 THEN 'HABIS'
        WHEN COALESCE(si.quantity, 0) < COALESCE(sr.min_qty, 3) THEN 'KURANG'
        ELSE 'CUKUP'
      END
    )
    ORDER BY p.model_name, pv.ram_rom, pv.color
  ), '[]'::json)
  INTO v_result
  FROM products p
  JOIN product_variants pv ON pv.product_id = p.id AND pv.active = true
  LEFT JOIN store_inventory si ON si.variant_id = pv.id AND si.store_id = p_store_id
  LEFT JOIN stores s ON s.id = p_store_id
  LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = s.grade
  WHERE p.status = 'active';

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_recommendations(UUID) TO authenticated;
