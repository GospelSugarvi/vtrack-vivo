-- PERFORMANCE MONITORING - SUPER SIMPLE VERSION
-- No complex functions, just basic monitoring
-- ==========================================

-- 1. BASIC INDEX MONITORING (NO ROUND FUNCTION)
CREATE OR REPLACE VIEW v_index_efficiency AS
SELECT 
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    idx_scan,
    CASE 
        WHEN idx_scan = 0 THEN '🔴 UNUSED'
        WHEN idx_scan < 10 THEN '🟡 LOW'
        ELSE '🟢 ACTIVE'
    END as usage_level
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- 2. BASIC TABLE MONITORING (NO ROUND FUNCTION)
CREATE OR REPLACE VIEW v_table_stats AS
SELECT 
    schemaname,
    relname as table_name,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows,
    CASE 
        WHEN n_dead_tup > n_live_tup THEN '🔴 HIGH BLOAT'
        WHEN n_dead_tup > (n_live_tup / 2) THEN '🟡 MODERATE BLOAT'
        ELSE '🟢 LOW BLOAT'
    END as bloat_status,
    last_vacuum,
    last_analyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- 3. TABLE SIZES (SIMPLE)
CREATE OR REPLACE VIEW v_table_sizes AS
SELECT 
    schemaname,
    relname as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
    n_live_tup as row_count
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC;

-- 4. SIMPLE PERFORMANCE ALERTS
CREATE OR REPLACE FUNCTION check_simple_alerts()
RETURNS TABLE (
    alert_type TEXT,
    message TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Unused indexes
    RETURN QUERY
    SELECT 
        'UNUSED_INDEX'::TEXT,
        format('Index %s on table %s is unused', indexrelname, relname)::TEXT
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0
    LIMIT 3;
    
    -- High bloat tables
    RETURN QUERY
    SELECT 
        'TABLE_BLOAT'::TEXT,
        format('Table %s has high bloat (%s dead rows)', relname, n_dead_tup)::TEXT
    FROM pg_stat_user_tables
    WHERE n_dead_tup > 1000 AND n_dead_tup > n_live_tup
    LIMIT 3;
END;
$$;

-- 5. SIMPLE PERFORMANCE TEST
CREATE OR REPLACE FUNCTION test_dashboard_speed()
RETURNS TABLE (
    function_name TEXT,
    result TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration_ms INTEGER;
BEGIN
    -- Test target dashboard function
    v_start_time := clock_timestamp();
    PERFORM * FROM get_target_dashboard('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);
    v_end_time := clock_timestamp();
    v_duration_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    RETURN QUERY SELECT 
        'get_target_dashboard'::TEXT,
        format('Executed in %s ms', v_duration_ms)::TEXT;
END;
$$;

-- 6. GRANT PERMISSIONS
GRANT SELECT ON v_index_efficiency TO authenticated;
GRANT SELECT ON v_table_stats TO authenticated;
GRANT SELECT ON v_table_sizes TO authenticated;
GRANT EXECUTE ON FUNCTION check_simple_alerts() TO authenticated;
GRANT EXECUTE ON FUNCTION test_dashboard_speed() TO authenticated;

-- 7. IMMEDIATE PERFORMANCE CHECK
SELECT '=== PERFORMANCE CHECK RESULTS ===' as section;

-- Check our critical tables
SELECT 
    'CRITICAL TABLES' as check_type,
    relname as table_name,
    pg_size_pretty(pg_total_relation_size('public.'||relname)) as size,
    n_live_tup as rows,
    n_dead_tup as dead_rows
FROM pg_stat_user_tables
WHERE relname IN ('sales_sell_out', 'dashboard_performance_metrics', 'user_targets', 'users')
ORDER BY pg_total_relation_size('public.'||relname) DESC;

-- Check indexes on critical tables
SELECT 
    'CRITICAL INDEXES' as check_type,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as scans,
    CASE WHEN idx_scan = 0 THEN '🔴 UNUSED' ELSE '🟢 USED' END as status
FROM pg_stat_user_indexes
WHERE relname IN ('sales_sell_out', 'dashboard_performance_metrics', 'user_targets')
ORDER BY idx_scan DESC;

-- Check dashboard metrics data
SELECT 
    'DASHBOARD METRICS' as check_type,
    COUNT(*) as total_records,
    COUNT(DISTINCT user_id) as users,
    COUNT(DISTINCT period_id) as periods
FROM dashboard_performance_metrics;

-- Simple alerts
SELECT 'ALERTS' as check_type, * FROM check_simple_alerts();

-- Test dashboard speed
SELECT 'SPEED TEST' as check_type, * FROM test_dashboard_speed();

SELECT '✅ Simple performance monitoring ready!' as result;
SELECT 'Use these views: v_index_efficiency, v_table_stats, v_table_sizes' as usage;