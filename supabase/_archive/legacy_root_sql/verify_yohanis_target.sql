-- Verify Yohanis Tipnoni target setup

-- 1. Get Yohanis user info
SELECT '=== YOHANIS USER INFO ===' as step;
SELECT id, email, full_name, role, area
FROM users
WHERE full_name ILIKE '%yohanis%tipnoni%'
OR full_name ILIKE '%tipnoni%';

-- 2. Check his targets
SELECT '=== USER TARGETS ===' as step;
SELECT ut.*, tp.period_name, tp.start_date, tp.end_date
FROM user_targets ut
JOIN target_periods tp ON ut.period_id = tp.id
JOIN users u ON ut.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 3. Check fokus targets
SELECT '=== FOKUS TARGETS ===' as step;
SELECT ft.*, fb.bundle_name, fb.product_types, tp.period_name
FROM fokus_targets ft
JOIN fokus_bundles fb ON ft.bundle_id = fb.id
JOIN target_periods tp ON ft.period_id = tp.id
JOIN users u ON ft.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%';

-- 4. Refresh materialized view
SELECT '=== REFRESHING VIEW ===' as step;
REFRESH MATERIALIZED VIEW v_target_dashboard;

-- 5. Check dashboard data for Yohanis
SELECT '=== DASHBOARD DATA ===' as step;
SELECT 
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
    warning_omzet,
    warning_fokus,
    fokus_details
FROM v_target_dashboard
WHERE full_name ILIKE '%tipnoni%'
AND period_name = 'Januari 2026';

-- 6. Test get_target_dashboard function
SELECT '=== FUNCTION TEST ===' as step;
-- Copy user_id and period_id from step 1 and 2, then uncomment:
-- SELECT * FROM get_target_dashboard('USER-ID-HERE', 'PERIOD-ID-HERE');

-- 7. Get credentials info
SELECT '=== LOGIN INFO ===' as step;
SELECT 
    'Email: ' || email as login_email,
    'Name: ' || full_name as name,
    'Role: ' || role as role,
    'Note: Ask admin for password or reset it' as password_note
FROM users
WHERE full_name ILIKE '%tipnoni%';
