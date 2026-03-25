-- Check stores table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stores' 
ORDER BY ordinal_position;
