-- CEK SEMUA TABEL AKTIVITAS SEKALIGUS

-- 1. attendance
SELECT 'attendance' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'attendance'
ORDER BY ordinal_position;

-- 2. sales_sell_out
SELECT 'sales_sell_out' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_sell_out'
ORDER BY ordinal_position;

-- 3. stock_validations
SELECT 'stock_validations' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'stock_validations'
ORDER BY ordinal_position;

-- 4. promotion_reports
SELECT 'promotion_reports' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'promotion_reports'
ORDER BY ordinal_position;

-- 5. follower_reports
SELECT 'follower_reports' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'follower_reports'
ORDER BY ordinal_position;

-- 6. report_follower (jika ada)
SELECT 'report_follower' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'report_follower'
ORDER BY ordinal_position;
