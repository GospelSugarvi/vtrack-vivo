-- CHECK ACTUAL COLUMN STRUCTURE IN SUPABASE
-- Let's see what columns actually exist
-- ==========================================

-- 1. Check pg_stat_user_tables structure
SELECT 'pg_stat_user_tables columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'pg_stat_user_tables' 
ORDER BY ordinal_position;

-- 2. Check pg_stat_user_indexes structure  
SELECT 'pg_stat_user_indexes columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'pg_stat_user_indexes' 
ORDER BY ordinal_position;

-- 3. Check what tables we actually have
SELECT 'Our actual tables:' as info;
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- 4. Simple test query
SELECT 'Simple test:' as info;
SELECT schemaname, relname 
FROM pg_stat_user_tables 
LIMIT 3;