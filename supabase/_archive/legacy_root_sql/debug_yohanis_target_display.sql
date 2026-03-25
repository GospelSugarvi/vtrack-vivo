-- Debug kenapa target Yohanis tidak muncul di UI

-- 1. Get Yohanis user ID
SELECT '=== 1. YOHANIS USER ID ===' as step;
SELECT id, email, full_name, role
FROM users
WHERE full_name ILIKE '%yohanis%tipnoni%';

-- 2. Check user_targets table
SELECT '=== 2. USER TARGETS (raw data) ===' as step;
SELECT ut.*, tp.period_name
FROM user_targets ut
JOIN target_periods tp ON ut.period_id = tp.id
JOIN users u ON ut.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 3. Check fokus_targets table
SELECT '=== 3. FOKUS TARGETS (raw data) ===' as step;
SELECT ft.*, fb.bundle_name, tp.period_name
FROM fokus_targets ft
JOIN fokus_bundles fb ON ft.bundle_id = fb.id
JOIN target_periods tp ON ft.period_id = tp.id
JOIN users u ON ft.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 4. Check dashboard_performance_metrics
SELECT '=== 4. DASHBOARD METRICS ===' as step;
SELECT dpm.*, tp.period_name
FROM dashboard_performance_metrics dpm
JOIN target_periods tp ON dpm.period_id = tp.id
JOIN users u ON dpm.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 5. Refresh materialized view
SELECT '=== 5. REFRESHING VIEW ===' as step;
REFRESH MATERIALIZED VIEW v_target_dashboard;
SELECT 'View refreshed successfully' as result;

-- 6. Check view data for Yohanis
SELECT '=== 6. VIEW DATA FOR YOHANIS ===' as step;
SELECT 
    user_id,
    full_name,
    period_name,
    target_omzet,
    actual_omzet,
    achievement_omzet_pct,
    target_fokus_total,
    actual_fokus_total,
    achievement_fokus_pct,
    time_gone_pct,
    status_omzet,
    status_fokus,
    fokus_details
FROM v_target_dashboard
WHERE full_name ILIKE '%tipnoni%'
AND period_name = 'Januari 2026';

-- 7. Test function directly with Yohanis ID
SELECT '=== 7. FUNCTION TEST ===' as step;
-- Copy user_id and period_id from step 1 and 2, then run:
-- SELECT * FROM get_target_dashboard('USER-ID-HERE', 'PERIOD-ID-HERE');

-- 8. Check what UI is querying
SELECT '=== 8. SIMULATE UI QUERY ===' as step;
-- This is what the UI should be calling:
-- Replace with actual Yohanis user_id
/*
SELECT * FROM get_target_dashboard(
    'YOHANIS-USER-ID-HERE',  -- from step 1
    NULL  -- NULL means get current period
);
*/
