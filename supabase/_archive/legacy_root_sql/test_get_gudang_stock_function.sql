-- Test apakah function get_gudang_stock sudah support parameter tanggal

-- 1. Cek signature function yang ada
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'get_gudang_stock';

-- 2. Test call function dengan tanggal hari ini
-- Ganti 'your-sator-id' dengan ID sator yang login
-- SELECT * FROM get_gudang_stock('a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'::uuid, '2026-02-04'::date);

-- 3. Cek data di tabel stok_gudang_harian
SELECT 
    tanggal,
    COUNT(*) as total_items,
    SUM(stok_gudang) as total_stok,
    MIN(created_at) as first_created,
    MAX(created_at) as last_created
FROM stok_gudang_harian
GROUP BY tanggal
ORDER BY tanggal DESC
LIMIT 10;
