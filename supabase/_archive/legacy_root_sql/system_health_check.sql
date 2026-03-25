-- System Health Check for VTrack
-- Run this periodically to ensure system is healthy
-- ==========================================

-- 1. Check trigger is working
SELECT 
    '=== TRIGGER STATUS ===' as check,
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers 
WHERE trigger_name = 'trigger_update_dashboard_metrics';

-- 2. Check data consistency
SELECT 
    '=== DATA CONSISTENCY ===' as check,
    COUNT(*) as total_users_with_sales,
    COUNT(DISTINCT dpm.user_id) as users_in_metrics,
    CASE 
        WHEN COUNT(*) = COUNT(DISTINCT dpm.user_id) THEN '✅ CONSISTENT'
        ELSE '⚠️ INCONSISTENT'
    END as status
FROM (
    SELECT DISTINCT promotor_id 
    FROM sales_sell_out 
    WHERE deleted_at IS NULL
) sales
LEFT JOIN dashboard_performance_metrics dpm ON sales.promotor_id = dpm.user_id;

-- 3. Check performance metrics
SELECT 
    '=== PERFORMANCE METRICS ===' as check,
    COUNT(*) as total_metrics_records,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT period_id) as unique_periods,
    MAX(last_updated) as latest_update
FROM dashboard_performance_metrics;

-- 4. Check target dashboard function performance
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM get_target_dashboard('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);

SELECT '✅ System Health Check Complete!' as result;