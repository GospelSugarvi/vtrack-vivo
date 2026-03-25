-- Check if required tables exist
SELECT 
    tablename,
    schemaname
FROM pg_tables 
WHERE schemaname = 'public'
AND tablename IN (
    'target_periods',
    'user_targets', 
    'users',
    'dashboard_performance_metrics',
    'fokus_bundles',
    'fokus_targets',
    'sales_sell_out'
)
ORDER BY tablename;
