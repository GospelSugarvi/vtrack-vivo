-- Cek kolom di tabel stock_validations
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_validations'
ORDER BY ordinal_position;
