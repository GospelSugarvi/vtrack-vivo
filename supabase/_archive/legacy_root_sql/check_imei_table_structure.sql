-- Cek struktur tabel imei_normalizations
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'imei_normalizations'
ORDER BY ordinal_position;

-- Cek sample data
SELECT * FROM imei_normalizations LIMIT 2;
