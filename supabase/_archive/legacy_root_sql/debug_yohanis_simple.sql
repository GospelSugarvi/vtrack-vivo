-- ==========================================
-- SIMPLE DEBUG FOR YOHANIS TARGET
-- ==========================================

-- 1. Yohanis User Info
SELECT '1. YOHANIS USER' as check, id, email, full_name, role
FROM users
WHERE full_name ILIKE '%yohanis%tipnoni%';

-- 2. User Targets
SELECT '2. USER TARGETS' as check, ut.*, tp.period_name
FROM user_targets ut
JOIN target_periods tp ON ut.period_id = tp.id
JOIN users u ON ut.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 3. Fokus Targets
SELECT '3. FOKUS TARGETS' as check, ft.*, fb.bundle_name, tp.period_name
FROM fokus_targets ft
JOIN fokus_bundles fb ON ft.bundle_id = fb.id
JOIN target_periods tp ON ft.period_id = tp.id
JOIN users u ON ft.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 4. Dashboard Metrics
SELECT '4. DASHBOARD METRICS' as check, dpm.*, tp.period_name
FROM dashboard_performance_metrics dpm
JOIN target_periods tp ON dpm.period_id = tp.id
JOIN users u ON dpm.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 5. Refresh View
REFRESH MATERIALIZED VIEW v_target_dashboard;
SELECT '5. VIEW REFRESHED' as check, 'Success' as status;

-- 6. View Data
SELECT '6. VIEW DATA' as check, *
FROM v_target_dashboard
WHERE full_name ILIKE '%tipnoni%'
AND period_name = 'Januari 2026';

-- 7. Test Function (copy user_id from result 1)
-- SELECT '7. FUNCTION TEST' as check, * 
-- FROM get_target_dashboard('PASTE-USER-ID-HERE', NULL);
