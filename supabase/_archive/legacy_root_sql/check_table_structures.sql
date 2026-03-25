-- Check sales_sell_out table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_sell_out' 
ORDER BY ordinal_position;

-- Check attendance table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'attendance' 
ORDER BY ordinal_position;

-- Check if there are any tables with 'attendance' in the name
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE '%attendance%';

-- Check fokus_products table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'fokus_products' 
ORDER BY ordinal_position;
