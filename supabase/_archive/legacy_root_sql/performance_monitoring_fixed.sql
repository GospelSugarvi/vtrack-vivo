-- PERFORMANCE MONITORING DASHBOARD (SUPABASE COMPATIBLE)
-- Real-time performance metrics and alerts
-- ==========================================

-- 1. CHECK IF PG_STAT_STATEMENTS IS AVAILABLE
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE NOTICE 'pg_stat_statements extension not available, using alternative monitoring';
    END IF;
END $$;

-- 2. INDEX EFFICIENCY MONITORING (WORKS WITHOUT EXTENSIONS)
CREATE OR REPLACE VIEW v_index_efficiency AS
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    CASE 
        WHEN idx_scan = 0 THEN '🔴 UNUSED'
        WHEN idx_scan < 10 THEN '🟡 LOW USAGE'
        WHEN idx_scan < 100 THEN '🟠 MODERATE'
        ELSE '🟢 HIGH USAGE'
    END as usage_level,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- 3. TABLE BLOAT MONITORING (WORKS WITHOUT EXTENSIONS)
CREATE OR REPLACE VIEW v_table_bloat AS
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_live_tup as live_tuples,
    n_dead_tup as dead_tuples,
    CASE 
        WHEN n_live_tup > 0 THEN ROUND((n_dead_tup::float / n_live_tup::float) * 100, 2)
        ELSE 0
    END as bloat_percentage,
    CASE 
        WHEN n_live_tup > 0 AND (n_dead_tup::float / n_live_tup::float) > 0.2 THEN '🔴 HIGH BLOAT'
        WHEN n_live_tup > 0 AND (n_dead_tup::float / n_live_tup::float) > 0.1 THEN '🟡 MODERATE BLOAT'
        ELSE '🟢 LOW BLOAT'
    END as bloat_status,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- 4. CONNECTION AND LOCK MONITORING (WORKS WITHOUT EXTENSIONS)
CREATE OR REPLACE VIEW v_connection_status AS
SELECT 
    state,
    COUNT(*) as connection_count,
    CASE 
        WHEN state = 'active' AND COUNT(*) > 10 THEN '🟡 HIGH ACTIVITY'
        WHEN state = 'idle in transaction' AND COUNT(*) > 5 THEN '🔴 POTENTIAL LOCKS'
        ELSE '🟢 NORMAL'
    END as status
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state;

-- 5. TABLE SIZE MONITORING
CREATE OR REPLACE VIEW v_table_sizes AS
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size,
    n_live_tup as row_count
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 6. FUNCTION CALL MONITORING (SIMPLIFIED)
CREATE OR REPLACE FUNCTION get_function_performance()
RETURNS TABLE (
    function_name TEXT,
    total_calls BIGINT,
    performance_status TEXT
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.proname::TEXT,
        COALESCE(ps.calls, 0) as total_calls,
        CASE 
            WHEN COALESCE(ps.calls, 0) = 0 THEN '⚪ NOT CALLED'
            WHEN ps.calls > 1000 THEN '🟢 HIGH USAGE'
            WHEN ps.calls > 100 THEN '🟡 MODERATE USAGE'
            ELSE '🔴 LOW USAGE'
        END as performance_status
    FROM pg_proc p
    LEFT JOIN pg_stat_user_functions ps ON p.oid = ps.funcid
    WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
        AND (p.proname LIKE '%target%' OR p.proname LIKE '%dashboard%' OR p.proname LIKE '%metrics%')
    ORDER BY COALESCE(ps.calls, 0) DESC;
END;
$$;

-- 7. PERFORMANCE ALERT SYSTEM (SIMPLIFIED)
CREATE OR REPLACE FUNCTION check_performance_alerts()
RETURNS TABLE (
    alert_type TEXT,
    severity TEXT,
    message TEXT,
    recommendation TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check for unused indexes
    RETURN QUERY
    SELECT 
        'UNUSED_INDEX'::TEXT,
        '🟡 MEDIUM'::TEXT,
        format('Index %s.%s is unused (%s scans)', schemaname, indexname, idx_scan)::TEXT,
        'Consider dropping unused index to save space'::TEXT
    FROM pg_stat_user_indexes
    WHERE idx_scan = 0
    LIMIT 5;
    
    -- Check for table bloat
    RETURN QUERY
    SELECT 
        'TABLE_BLOAT'::TEXT,
        '🟠 MEDIUM'::TEXT,
        format('Table %s.%s has %s%% bloat', schemaname, tablename, 
               ROUND((n_dead_tup::float / GREATEST(n_live_tup, 1)::float) * 100, 2))::TEXT,
        'Run VACUUM or ANALYZE on this table'::TEXT
    FROM pg_stat_user_tables
    WHERE n_live_tup > 100 AND (n_dead_tup::float / GREATEST(n_live_tup, 1)::float) > 0.2
    LIMIT 3;
    
    -- Check for long-running transactions
    RETURN QUERY
    SELECT 
        'LONG_TRANSACTION'::TEXT,
        '🔴 HIGH'::TEXT,
        format('Transaction running for %s', age(now(), query_start))::TEXT,
        'Investigate and potentially terminate long-running transaction'::TEXT
    FROM pg_stat_activity
    WHERE state = 'idle in transaction'
        AND age(now(), query_start) > interval '5 minutes'
    LIMIT 3;
    
    -- Check for large tables without recent vacuum
    RETURN QUERY
    SELECT 
        'VACUUM_NEEDED'::TEXT,
        '🟡 MEDIUM'::TEXT,
        format('Table %s.%s has not been vacuumed recently', schemaname, tablename)::TEXT,
        'Consider running VACUUM ANALYZE on this table'::TEXT
    FROM pg_stat_user_tables
    WHERE n_live_tup > 1000 
        AND (last_vacuum IS NULL OR last_vacuum < now() - interval '7 days')
        AND (last_autovacuum IS NULL OR last_autovacuum < now() - interval '7 days')
    LIMIT 3;
END;
$$;

-- 8. COMPREHENSIVE PERFORMANCE REPORT (SIMPLIFIED)
CREATE OR REPLACE FUNCTION generate_performance_report()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    v_report TEXT := '';
    v_total_size TEXT;
    v_index_count INTEGER;
    v_table_count INTEGER;
    v_active_connections INTEGER;
    v_alert_count INTEGER;
BEGIN
    -- Database overview
    SELECT pg_size_pretty(pg_database_size(current_database())) INTO v_total_size;
    SELECT COUNT(*) FROM pg_stat_user_tables INTO v_table_count;
    SELECT COUNT(*) FROM pg_stat_user_indexes INTO v_index_count;
    SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active' INTO v_active_connections;
    SELECT COUNT(*) FROM check_performance_alerts() INTO v_alert_count;
    
    v_report := format(E'📊 PERFORMANCE REPORT - %s\n', now()::date);
    v_report := v_report || format(E'=====================================\n');
    v_report := v_report || format(E'Database Size: %s\n', v_total_size);
    v_report := v_report || format(E'Tables: %s | Indexes: %s\n', v_table_count, v_index_count);
    v_report := v_report || format(E'Active Connections: %s\n', v_active_connections);
    v_report := v_report || format(E'Performance Alerts: %s\n\n', v_alert_count);
    
    -- Top performance issues
    IF v_alert_count > 0 THEN
        v_report := v_report || format(E'🚨 PERFORMANCE ALERTS:\n');
        v_report := v_report || (
            SELECT string_agg(format('%s: %s', severity, message), E'\n')
            FROM check_performance_alerts()
            LIMIT 5
        );
    ELSE
        v_report := v_report || format(E'✅ No performance alerts detected\n');
    END IF;
    
    v_report := v_report || format(E'\n\n✅ Report generated successfully!');
    
    RETURN v_report;
END;
$$;

-- 9. TARGET DASHBOARD PERFORMANCE TEST
CREATE OR REPLACE FUNCTION test_target_dashboard_performance()
RETURNS TABLE (
    test_name TEXT,
    execution_time_ms NUMERIC,
    status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_duration NUMERIC;
BEGIN
    -- Test 1: Original function
    v_start_time := clock_timestamp();
    PERFORM * FROM get_target_dashboard('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);
    v_end_time := clock_timestamp();
    v_duration := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    RETURN QUERY SELECT 
        'Original get_target_dashboard'::TEXT,
        ROUND(v_duration, 2),
        CASE WHEN v_duration < 200 THEN '🟢 FAST' WHEN v_duration < 500 THEN '🟡 MODERATE' ELSE '🔴 SLOW' END;
    
    -- Test 2: Optimized function (if exists)
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_target_dashboard_optimized') THEN
        v_start_time := clock_timestamp();
        PERFORM * FROM get_target_dashboard_optimized('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);
        v_end_time := clock_timestamp();
        v_duration := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        RETURN QUERY SELECT 
            'Optimized get_target_dashboard_optimized'::TEXT,
            ROUND(v_duration, 2),
            CASE WHEN v_duration < 200 THEN '🟢 FAST' WHEN v_duration < 500 THEN '🟡 MODERATE' ELSE '🔴 SLOW' END;
    END IF;
END;
$$;

-- 10. GRANT PERMISSIONS
GRANT SELECT ON v_index_efficiency TO authenticated;
GRANT SELECT ON v_table_bloat TO authenticated;
GRANT SELECT ON v_connection_status TO authenticated;
GRANT SELECT ON v_table_sizes TO authenticated;
GRANT EXECUTE ON FUNCTION get_function_performance() TO authenticated;
GRANT EXECUTE ON FUNCTION check_performance_alerts() TO authenticated;
GRANT EXECUTE ON FUNCTION generate_performance_report() TO authenticated;
GRANT EXECUTE ON FUNCTION test_target_dashboard_performance() TO authenticated;

-- 11. SAMPLE MONITORING QUERIES
SELECT '=== PERFORMANCE MONITORING READY (SUPABASE COMPATIBLE) ===' as status;
SELECT 'Run these queries to monitor performance:' as instructions;
SELECT '1. SELECT * FROM v_index_efficiency;' as query1;
SELECT '2. SELECT * FROM v_table_bloat;' as query2;
SELECT '3. SELECT * FROM v_table_sizes;' as query3;
SELECT '4. SELECT * FROM check_performance_alerts();' as query4;
SELECT '5. SELECT generate_performance_report();' as query5;
SELECT '6. SELECT * FROM test_target_dashboard_performance();' as query6;

-- 12. QUICK PERFORMANCE CHECK
SELECT '=== QUICK PERFORMANCE CHECK ===' as section;

-- Check critical indexes
SELECT 
    'INDEX CHECK' as check_type,
    COUNT(*) as total_indexes,
    COUNT(CASE WHEN idx_scan = 0 THEN 1 END) as unused_indexes,
    COUNT(CASE WHEN idx_scan > 1000 THEN 1 END) as high_usage_indexes
FROM pg_stat_user_indexes;

-- Check table sizes
SELECT 
    'TABLE SIZE CHECK' as check_type,
    tablename,
    pg_size_pretty(pg_total_relation_size('public.'||tablename)) as size,
    n_live_tup as rows
FROM pg_stat_user_tables
WHERE tablename IN ('sales_sell_out', 'dashboard_performance_metrics', 'user_targets')
ORDER BY pg_total_relation_size('public.'||tablename) DESC;

-- Check dashboard metrics data
SELECT 
    'METRICS DATA CHECK' as check_type,
    COUNT(*) as total_records,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT period_id) as unique_periods,
    MAX(last_updated) as latest_update
FROM dashboard_performance_metrics;

SELECT '✅ Performance monitoring setup complete!' as result;