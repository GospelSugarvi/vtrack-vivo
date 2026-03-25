-- FIX V2 get_gudang_stock - Removed problematic filters
CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SELECT COALESCE(json_agg(
    json_build_object(
      'product_id', p.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'qty', COALESCE(sgh.stok_gudang, 0),
      'otw', COALESCE(sgh.stok_otw, 0),
      'category', CASE 
         WHEN COALESCE(sgh.stok_gudang, 0) = 0 THEN 'empty'
         WHEN COALESCE(sgh.stok_gudang, 0) < 5 THEN 'critical'
         WHEN COALESCE(sgh.stok_gudang, 0) < 10 THEN 'enough'
         ELSE 'plenty'
       END
    )
  ), '[]'::json)
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  LEFT JOIN stok_gudang_harian sgh ON p.id = sgh.product_id 
       AND pv.id = sgh.variant_id 
       AND sgh.tanggal = CURRENT_DATE
  WHERE sgh.id IS NOT NULL  -- Only show products with stock data today
  ORDER BY pv.srp ASC;
END;
$$;
