-- Debug kenapa kuantitas tidak muncul

-- 1. Cek data stok untuk hari ini
SELECT 
    p.model_name,
    pv.ram_rom,
    pv.color,
    sgh.stok_gudang,
    sgh.stok_otw,
    sgh.tanggal,
    sgh.created_at
FROM stok_gudang_harian sgh
JOIN products p ON sgh.product_id = p.id
JOIN product_variants pv ON sgh.variant_id = pv.id
WHERE sgh.tanggal = '2026-02-05'
ORDER BY p.model_name;

-- 2. Test function get_gudang_stock untuk hari ini
-- Ganti dengan ID sator yang login (Antonio)
SELECT * FROM get_gudang_stock(
    'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'::uuid,
    '2026-02-05'::date
);
