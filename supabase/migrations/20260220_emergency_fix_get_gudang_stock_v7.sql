-- EMERGENCY FIX V7: FINAL STABLE VERSION
-- 1. Kembali ke LEFT JOIN: Produk pasti muncul (tidak layar kosong).
-- 2. Mengambil info 5G (network_type) dengan benar.
-- 3. Menggunakan nama tabel dan kolom yang sudah diverifikasi (stok_gudang_harian, model_name).

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
    p.model_name as product_name, -- Fix: model_name
    v.ram_rom as variant,         -- Fix: ram_rom
    v.color,                      -- Fix: color
    v.srp as price,               -- Fix: srp
    p.network_type,               -- Fix: 5G
    COALESCE(s.stok_gudang, 0) as qty,
    COALESCE(s.stok_otw, 0) as otw,
    s.created_at as last_updated
  FROM products p
  JOIN product_variants v ON p.id = v.product_id
  LEFT JOIN stok_gudang_harian s ON 
    s.variant_id = v.id AND            
    s.tanggal = p_tanggal AND          
    s.created_by = p_sator_id          
  WHERE p.status = 'active'
    AND v.active = true
    AND p.deleted_at IS NULL
    AND v.deleted_at IS NULL
  ORDER BY p.model_name, v.srp;
END;
$$ LANGUAGE plpgsql;
