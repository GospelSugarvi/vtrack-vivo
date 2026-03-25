-- Check all tables needed for chat performance panel

-- 1. Check stores table
SELECT 'stores' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stores' 
ORDER BY ordinal_position;

-- 2. Check assignments_promotor_store table
SELECT 'assignments_promotor_store' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'assignments_promotor_store' 
ORDER BY ordinal_position;

-- 3. Check users table
SELECT 'users' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'users' 
ORDER BY ordinal_position;

-- 4. Check sales_sell_out table
SELECT 'sales_sell_out' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_sell_out' 
ORDER BY ordinal_position;

-- 5. Check product_variants table
SELECT 'product_variants' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'product_variants' 
ORDER BY ordinal_position;

-- 6. Check fokus_products table
SELECT 'fokus_products' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'fokus_products' 
ORDER BY ordinal_position;

-- 7. Check user_targets table
SELECT 'user_targets' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'user_targets' 
ORDER BY ordinal_position;

-- 8. Check allbrand_reports table
SELECT 'allbrand_reports' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'allbrand_reports' 
ORDER BY ordinal_position;

-- 9. Check attendance table
SELECT 'attendance' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'attendance' 
ORDER BY ordinal_position;

-- 10. Check stock_movement_log table
SELECT 'stock_movement_log' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_movement_log' 
ORDER BY ordinal_position;
