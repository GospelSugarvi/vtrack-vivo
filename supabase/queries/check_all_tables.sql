-- Cek daftar semua tabel di public schema untuk menemukan tabel stok gudang yang benar
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public'
ORDER BY table_name;

-- Cek juga kolom-kolom pada tabel yang dicurigai (misal yang ada kata 'stock' atau 'gudang')
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND (table_name LIKE '%stock%' OR table_name LIKE '%gudang%')
ORDER BY table_name, ordinal_position;
