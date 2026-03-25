-- SIMPLE PERFORMANCE CHECK
-- Compatible with Supabase
-- ==========================================

-- 1. CHECK TABLE SIZES
SELECT 
    'TABLE SIZES' as section,
    schemaname,
    relname as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size
FROM pg_stat_user_tables 
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC
LIMIT 10;

-- 2. CHECK INDEX USAGE
SELECT 
    'INDEX USAGE' as section,
    schemaname,
    relname as table_name,
    indexrelname as index_name,
    idx_scan as scans,
    CASE 
        WHEN idx_scan = 0 THEN '🔴 UNUSED'
        WHEN idx_scan < 100 THEN '🟡 LOW'
        ELSE '🟢 ACTIVE'
    END as status
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC
LIMIT 15;

-- 3. TEST TARGET DASHBOARD PERFORMANCE
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM get_target_dashboard('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);

-- 4. CHECK DASHBOARD METRICS DATA
SELECT 
    'METRICS CHECK' as section,
    COUNT(*) as total_records,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT period_id) as unique_periods,
    MAX(last_updated) as latest_update
FROM dashboard_performance_metrics;

-- 5. CHECK SALES DATA VOLUME
SELECT 
    'SALES VOLUME' as section,
    COUNT(*) as total_sales,
    COUNT(DISTINCT promotor_id) as unique_promotors,
    MIN(transaction_date) as earliest_sale,
    MAX(transaction_date) as latest_sale
FROM sales_sell_out
WHERE deleted_at IS NULL;

SELECT '✅ Performance check complete!' as result;