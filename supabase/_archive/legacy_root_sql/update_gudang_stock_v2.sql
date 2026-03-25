-- Update get_gudang_stock to show ALL products (including empty stock)
-- Sort: products with stock first, empty stock at bottom
DROP FUNCTION IF EXISTS get_gudang_stock(UUID);

CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    json_agg(
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
      ) ORDER BY 
        CASE WHEN COALESCE(sgh.stok_gudang, 0) = 0 THEN 1 ELSE 0 END, -- Empty stock last
        pv.srp ASC -- Then by price
    ),
    '[]'::json
  )
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  LEFT JOIN stok_gudang_harian sgh ON p.id = sgh.product_id 
       AND pv.id = sgh.variant_id 
       AND sgh.tanggal = CURRENT_DATE
  WHERE pv.active = true;  -- Show ALL active products
$$;

-- Function to check if stock already created today
DROP FUNCTION IF EXISTS get_stok_gudang_status();
CREATE OR REPLACE FUNCTION get_stok_gudang_status()
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_build_object(
    'has_data', EXISTS(SELECT 1 FROM stok_gudang_harian WHERE tanggal = CURRENT_DATE),
    'created_by', (
      SELECT u.full_name 
      FROM stok_gudang_harian sgh
      JOIN users u ON sgh.created_by = u.id
      WHERE sgh.tanggal = CURRENT_DATE
      LIMIT 1
    ),
    'created_at', (
      SELECT sgh.created_at 
      FROM stok_gudang_harian sgh
      WHERE sgh.tanggal = CURRENT_DATE
      ORDER BY sgh.created_at ASC
      LIMIT 1
    ),
    'total_items', (
      SELECT COUNT(DISTINCT (product_id, variant_id))
      FROM stok_gudang_harian 
      WHERE tanggal = CURRENT_DATE
    )
  );
$$;

GRANT EXECUTE ON FUNCTION get_gudang_stock(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_stok_gudang_status() TO authenticated;
