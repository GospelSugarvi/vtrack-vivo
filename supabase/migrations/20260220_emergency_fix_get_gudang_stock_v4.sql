-- EMERGENCY FIX V4: FINAL CORRECT QUERY
-- 1. Menggunakan nama tabel stok yang BENAR: `stok_gudang_harian`
-- 2. Menggunakan tabel varian yang BENAR: `product_variants` (dengan kolom `color` dan `ram_rom`)
-- 3. Menggunakan nama kolom produk yang BENAR: `model_name`
-- 4. Logika 5G (network_type) disertakan

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
    p.model_name as product_name, -- Gunakan model_name
    v.ram_rom as variant,         -- Gunakan ram_rom dari product_variants
    v.color,                      -- Gunakan color dari product_variants
    v.srp as price,               -- Gunakan srp sebagai price
    p.network_type,               -- 5G info
    COALESCE(s.stok_gudang, 0) as qty, -- Gunakan nama kolom stok_gudang
    COALESCE(s.stok_otw, 0) as otw,    -- Gunakan nama kolom stok_otw
    s.created_at as last_updated       -- Gunakan created_at
  FROM products p
  JOIN product_variants v ON p.id = v.product_id
  LEFT JOIN stok_gudang_harian s ON 
    s.variant_id = v.id AND            -- Join stok by Variant ID (unik per warna)
    s.tanggal = p_tanggal AND          -- Filter tanggal
    s.created_by = p_sator_id          -- Filter user (sator)
  WHERE p.status = 'active' AND v.active = true -- Hanya produk & varian aktif
  ORDER BY p.model_name, v.srp;
END;
$$ LANGUAGE plpgsql;
