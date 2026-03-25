-- EMERGENCY FIX V6: Back to LEFT JOIN for safety
-- Mengembalikan produk agar terlihat (walaupun stok mungkin 0 jika join gagal)
-- Ini untuk memastikan user tidak melihat layar kosong.

DROP FUNCTION IF EXISTS get_gudang_stock(uuid, date);

CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id uuid, p_tanggal date)
RETURNS TABLE (
  product_id uuid,
  variant_id uuid,
  product_name text,
  variant text,
  color text,
  price numeric,
  network_type text,
  qty integer,
  otw integer,
  last_updated timestamp with time zone
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as product_id,
    v.id as variant_id,
    p.model_name as product_name, 
    v.ram_rom as variant,         
    v.color,                      
    v.srp as price,               
    p.network_type,               
    COALESCE(s.stok_gudang, 0) as qty, 
    COALESCE(s.stok_otw, 0) as otw,    
    s.created_at as last_updated       
  FROM products p
  JOIN product_variants v ON p.id = v.product_id
  LEFT JOIN stok_gudang_harian s ON 
    s.variant_id = v.id AND            
    s.tanggal = p_tanggal AND          
    s.created_by = p_sator_id          
  WHERE p.status = 'active' AND v.active = true
  ORDER BY p.model_name, v.srp;
END;
$$ LANGUAGE plpgsql;
