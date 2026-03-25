-- DROP and recreate to avoid conflicts
DROP FUNCTION IF EXISTS get_gudang_stock(UUID);

CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    json_agg(
      json_build_object(
        'product_id', sgh.product_id,
        'product_name', p.model_name,
        'variant', pv.ram_rom,
        'color', pv.color,
        'price', pv.srp,
        'qty', sgh.stok_gudang,
        'otw', sgh.stok_otw,
        'category', sgh.status
      )
    ),
    '[]'::json
  )
  FROM stok_gudang_harian sgh
  JOIN products p ON sgh.product_id = p.id
  JOIN product_variants pv ON sgh.variant_id = pv.id
  WHERE sgh.tanggal = CURRENT_DATE;
$$;
