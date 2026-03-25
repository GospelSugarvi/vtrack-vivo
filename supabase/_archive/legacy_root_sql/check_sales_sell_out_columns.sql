-- Cek kolom di tabel sales_sell_out
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_sell_out'
ORDER BY ordinal_position;
