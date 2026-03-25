-- Cek kolom di tabel promotion_reports
SELECT 'promotion_reports' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'promotion_reports'
ORDER BY ordinal_position;

-- Cek kolom di tabel follower_reports
SELECT 'follower_reports' as table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'follower_reports'
ORDER BY ordinal_position;
