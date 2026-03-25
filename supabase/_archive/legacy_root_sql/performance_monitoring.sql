-- PERFORMANCE MONITORING DASHBOARD
-- Real-time performance metrics and alerts
-- ==========================================

-- 1. QUERY PERFORMANCE MONITORING
CREATE OR REPLACE VIEW v_query_performance AS
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time,
    min_time,
    stddev_time,
    ROUND((total_time / calls)::numeric, 2) as avg_time_ms,
    CASE 
        WHEN mean_time > 1000 THEN '🔴 SLOW'
        WHEN mean_time > 500 THEN '🟡 MODERATE'
        ELSE '🟢 FAST'
    END as performance_status
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
    AND query NOT LIKE '%information_schema%'
ORDER BY total_time DESC
LIMIT 20;

-- 2. INDEX EFFICIENCY MONITORING
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

-- 3. TABLE BLOAT MONITORING
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

-- 4. CONNECTION AND LOCK MONITORING
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

-- 5. TRIGGER PERFORMANCE MONITORING
CREATE OR REPLACE VIEW v_trigger_performance AS
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    'Check execution time in application logs' as performance_note
FROM information_schema.triggers 
WHERE trigger_schema = 'public';

-- 6. FUNCTION CALL MONITORING
CREATE OR REPLACE FUNCTION get_function_performance()
RETURNS TABLE (
    function_name TEXT,
    total_calls BIGINT,
    total_time_ms NUMERIC,
    avg_time_ms NUMERIC,
    performance_status TEXT
) 
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.proname::TEXT,
        COALESCE(ps.calls, 0) as total_calls,
        COALESCE(ps.total_time, 0) as total_time_ms,
        CASE 
            WHEN COALESCE(ps.calls, 0) > 0 
            THEN ROUND(COALESCE(ps.total_time, 0) / ps.calls, 2)
            ELSE 0
        END as avg_time_ms,
        CASE 
            WHEN COALESCE(ps.calls, 0) = 0 THEN '⚪ NOT CALLED'
            WHEN ps.calls > 0 AND (ps.total_time / ps.calls) > 1000 THEN '🔴 SLOW'
            WHEN ps.calls > 0 AND (ps.total_time / ps.calls) > 100 THEN '🟡 MODERATE'
            ELSE '🟢 FAST'
        END as performance_status
    FROM pg_proc p
    LEFT JOIN pg_stat_user_functions ps ON p.oid = ps.funcid
    WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
        AND p.proname LIKE '%target%' OR p.proname LIKE '%dashboard%' OR p.proname LIKE '%metrics%'
    ORDER BY COALESCE(ps.total_time, 0) DESC;
END;
$$;

-- 7. PERFORMANCE ALERT SYSTEM
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
    -- Check for slow queries
    RETURN QUERY
    SELECT 
        'SLOW_QUERY'::TEXT,
        '🔴 HIGH'::TEXT,
        format('Query with avg time %s ms detected', ROUND(mean_time, 2))::TEXT,
        'Consider adding indexes or optimizing query'::TEXT
    FROM pg_stat_statements
    WHERE mean_time > 1000
    LIMIT 5;
    
    -- Check for unused indexes
    RETURN QUERY
    SELECT 
        'UNUSED_INDEX'::TEXT,
        '🟡 MEDIUM'::TEXT,
        format('Index %s.%s is unused', schemaname, indexname)::TEXT,
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
END;
$$;

-- 8. COMPREHENSIVE PERFORMANCE REPORT
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
BEGIN
    -- Database overview
    SELECT pg_size_pretty(pg_database_size(current_database())) INTO v_total_size;
    SELECT COUNT(*) FROM pg_stat_user_tables INTO v_table_count;
    SELECT COUNT(*) FROM pg_stat_user_indexes INTO v_index_count;
    SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active' INTO v_active_connections;
    
    v_report := format(E'📊 PERFORMANCE REPORT - %s\n', now()::date);
    v_report := v_report || format(E'=====================================\n');
    v_report := v_report || format(E'Database Size: %s\n', v_total_size);
    v_report := v_report || format(E'Tables: %s | Indexes: %s\n', v_table_count, v_index_count);
    v_report := v_report || format(E'Active Connections: %s\n\n', v_active_connections);
    
    -- Top performance issues
    v_report := v_report || format(E'🚨 PERFORMANCE ALERTS:\n');
    v_report := v_report || (
        SELECT string_agg(format('%s: %s', severity, message), E'\n')
        FROM check_performance_alerts()
        LIMIT 5
    );
    
    v_report := v_report || format(E'\n\n✅ Report generated successfully!');
    
    RETURN v_report;
END;
$$;

-- 9. GRANT PERMISSIONS
GRANT SELECT ON v_query_performance TO authenticated;
GRANT SELECT ON v_index_efficiency TO authenticated;
GRANT SELECT ON v_table_bloat TO authenticated;
GRANT SELECT ON v_connection_status TO authenticated;
GRANT SELECT ON v_trigger_performance TO authenticated;
GRANT EXECUTE ON FUNCTION get_function_performance() TO authenticated;
GRANT EXECUTE ON FUNCTION check_performance_alerts() TO authenticated;
GRANT EXECUTE ON FUNCTION generate_performance_report() TO authenticated;

-- 10. SAMPLE MONITORING QUERIES
SELECT '=== PERFORMANCE MONITORING READY ===' as status;
SELECT 'Run these queries to monitor performance:' as instructions;
SELECT '1. SELECT * FROM v_query_performance;' as query1;
SELECT '2. SELECT * FROM v_index_efficiency;' as query2;
SELECT '3. SELECT * FROM v_table_bloat;' as query3;
SELECT '4. SELECT * FROM check_performance_alerts();' as query4;
SELECT '5. SELECT generate_performance_report();' as query5;