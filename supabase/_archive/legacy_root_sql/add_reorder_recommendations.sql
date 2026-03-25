-- ADD get_reorder_recommendations function
DROP FUNCTION IF EXISTS get_reorder_recommendations(UUID, UUID);
CREATE OR REPLACE FUNCTION get_reorder_recommendations(
  p_sator_id UUID,
  p_store_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(
    json_build_object(
      'product_id', p.id,
      'variant_id', pv.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'gudang_stock', COALESCE(sgh.stok_gudang, 0),
      'reorder_qty', CASE 
        WHEN COALESCE(sgh.stok_gudang, 0) > 10 THEN 3
        WHEN COALESCE(sgh.stok_gudang, 0) > 5 THEN 2
        WHEN COALESCE(sgh.stok_gudang, 0) > 0 THEN 1
        ELSE 0
      END
    )
  ), '[]'::json)
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  LEFT JOIN stok_gudang_harian sgh ON p.id = sgh.product_id 
    AND pv.id = sgh.variant_id 
    AND sgh.tanggal = CURRENT_DATE
  WHERE COALESCE(sgh.stok_gudang, 0) > 0;
$$;

GRANT EXECUTE ON FUNCTION get_reorder_recommendations(UUID, UUID) TO authenticated;
