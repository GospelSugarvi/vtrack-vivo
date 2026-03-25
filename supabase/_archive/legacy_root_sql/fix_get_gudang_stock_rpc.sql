-- FIX function get_gudang_stock to read from the correct daily table
CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- FIX: Read from stok_gudang_harian instead of warehouse_stock
  SELECT COALESCE(json_agg(
    json_build_object(
      'product_id', p.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'qty', COALESCE(sgh.stok_gudang, 0), -- Read from daily table
      'otw', COALESCE(sgh.stok_otw, 0),
      'category', CASE 
         WHEN sgh.id IS NOT NULL THEN COALESCE(sgh.status, 'empty')
         ELSE 'empty'
       END
    )
  ), '[]'::json)
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  -- Join with daily stock for TODAY
  LEFT JOIN stok_gudang_harian sgh ON p.id = sgh.product_id 
       AND pv.id = sgh.variant_id 
       AND sgh.tanggal = CURRENT_DATE
  WHERE p.status = 'active' AND pv.active = true
  ORDER BY pv.srp ASC;
END;
$$;
