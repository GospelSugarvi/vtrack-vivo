-- Test the target dashboard system

-- 1. Check if functions exist
SELECT 'Functions check:' as test;
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('get_time_gone_percentage', 'calculate_target_achievement', 'get_target_dashboard')
ORDER BY routine_name;

-- 2. Check if view exists
SELECT 'View check:' as test;
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name = 'v_target_dashboard';

-- 3. Get a sample user and period
SELECT 'Sample data:' as test;
SELECT u.id as user_id, u.full_name, u.role, tp.id as period_id, tp.period_name
FROM users u
CROSS JOIN target_periods tp
WHERE u.role = 'promotor' 
AND u.deleted_at IS NULL
AND tp.deleted_at IS NULL
LIMIT 1;

-- 4. Test get_target_dashboard function with sample data
-- Replace with actual IDs from query above
SELECT 'Function test (replace IDs):' as test;
-- SELECT * FROM get_target_dashboard('user-id-here', 'period-id-here');

-- 5. Check view data
SELECT 'View data sample:' as test;
SELECT user_id, full_name, period_name, target_omzet, actual_omzet, 
       achievement_omzet_pct, target_fokus_total, actual_fokus_total,
       achievement_fokus_pct, time_gone_pct, status_omzet, status_fokus
FROM v_target_dashboard
LIMIT 5;
