-- Cek struktur tabel products
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = 'products'
ORDER BY ordinal_position;

-- Cek sample data
SELECT * FROM products LIMIT 5;
