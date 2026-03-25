-- Reset Target Periods System
-- WARNING: This will delete all existing target periods and related data

-- ==========================================
-- STEP 1: Delete all related data (in correct order)
-- ==========================================

-- Delete dashboard_performance_metrics (references period_id)
DELETE FROM dashboard_performance_metrics;

-- Delete fokus targets
DELETE FROM fokus_targets;

-- Delete user targets
DELETE FROM user_targets;

-- Delete fokus bundles
DELETE FROM fokus_bundles;

-- Delete weekly targets (if exists)
DELETE FROM weekly_targets WHERE TRUE;

-- Delete target periods
DELETE FROM target_periods;

-- ==========================================
-- STEP 2: Verify deletion
-- ==========================================
SELECT 
    'target_periods' as table_name,
    COUNT(*) as remaining_rows
FROM target_periods
UNION ALL
SELECT 
    'user_targets' as table_name,
    COUNT(*) as remaining_rows
FROM user_targets
UNION ALL
SELECT 
    'fokus_bundles' as table_name,
    COUNT(*) as remaining_rows
FROM fokus_bundles
UNION ALL
SELECT 
    'fokus_targets' as table_name,
    COUNT(*) as remaining_rows
FROM fokus_targets
UNION ALL
SELECT 
    'dashboard_performance_metrics' as table_name,
    COUNT(*) as remaining_rows
FROM dashboard_performance_metrics;

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ All target periods and related data deleted!' as status;
SELECT 'You can now create new periods using the new system' as info;
