-- Cek kolom di tabel stock_movement_log
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_movement_log'
ORDER BY ordinal_position;
