-- Test Target Achievement System
-- Run this to verify everything works

-- ==========================================
-- TEST 1: Time-Gone Calculation
-- ==========================================
SELECT '=== TEST 1: Time-Gone Calculation ===' as test;

SELECT 
    period_name,
    start_date,
    end_date,
    CURRENT_DATE as today,
    (CURRENT_DATE - start_date + 1) as days_passed,
    (end_date - start_date + 1) as total_days,
    get_time_gone_percentage(id) as time_gone_pct
FROM target_periods
WHERE deleted_at IS NULL
ORDER BY start_date DESC
LIMIT 3;

-- ==========================================
-- TEST 2: Check User Targets
-- ==========================================
SELECT '=== TEST 2: User Targets Data ===' as test;

SELECT 
    u.full_name,
    u.role,
    tp.period_name,
    ut.target_sell_out as target_omzet,
    ut.target_fokus,
    dpm.total_omzet_real as actual_omzet,
    dpm.total_units_focus as actual_fokus
FROM users u
JOIN user_targets ut ON ut.user_id = u.id
JOIN target_periods tp ON tp.id = ut.period_id
LEFT JOIN dashboard_performance_metrics dpm ON dpm.user_id = u.id AND dpm.period_id = ut.period_id
WHERE u.role = 'promotor'
AND u.deleted_at IS NULL
AND tp.deleted_at IS NULL
ORDER BY u.full_name
LIMIT 5;

-- ==========================================
-- TEST 3: Calculate Achievement for One User
-- ==========================================
SELECT '=== TEST 3: Achievement Calculation ===' as test;

SELECT * FROM calculate_target_achievement(
    (SELECT id FROM users WHERE role = 'promotor' AND deleted_at IS NULL LIMIT 1),
    (SELECT id FROM target_periods WHERE deleted_at IS NULL ORDER BY start_date DESC LIMIT 1)
);

-- ==========================================
-- TEST 4: Get Target Dashboard
-- ==========================================
SELECT '=== TEST 4: Target Dashboard ===' as test;

SELECT 
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
    warning_fokus
FROM get_target_dashboard(
    (SELECT id FROM users WHERE role = 'promotor' AND deleted_at IS NULL LIMIT 1),
    NULL
);

-- ==========================================
-- TEST 5: Check All Users with Warnings
-- ==========================================
SELECT '=== TEST 5: Users with Warnings ===' as test;

WITH current_period AS (
    SELECT id FROM target_periods 
    WHERE CURRENT_DATE BETWEEN start_date AND end_date 
    AND deleted_at IS NULL 
    LIMIT 1
)
SELECT 
    u.full_name,
    u.role,
    td.achievement_omzet_pct,
    td.time_gone_pct,
    td.status_omzet,
    td.warning_omzet,
    td.achievement_fokus_pct,
    td.status_fokus,
    td.warning_fokus
FROM users u
CROSS JOIN current_period cp
LEFT JOIN LATERAL get_target_dashboard(u.id, cp.id) td ON true
WHERE u.role IN ('promotor', 'sator', 'spv')
AND u.deleted_at IS NULL
AND (td.warning_omzet = true OR td.warning_fokus = true)
ORDER BY u.full_name;

-- ==========================================
-- TEST 6: Summary Statistics
-- ==========================================
SELECT '=== TEST 6: Summary Statistics ===' as test;

WITH current_period AS (
    SELECT id FROM target_periods 
    WHERE CURRENT_DATE BETWEEN start_date AND end_date 
    AND deleted_at IS NULL 
    LIMIT 1
),
all_achievements AS (
    SELECT 
        u.id,
        u.full_name,
        u.role,
        td.*
    FROM users u
    CROSS JOIN current_period cp
    LEFT JOIN LATERAL get_target_dashboard(u.id, cp.id) td ON true
    WHERE u.role IN ('promotor', 'sator', 'spv')
    AND u.deleted_at IS NULL
)
SELECT 
    role,
    COUNT(*) as total_users,
    COUNT(*) FILTER (WHERE warning_omzet = true) as omzet_warnings,
    COUNT(*) FILTER (WHERE warning_fokus = true) as fokus_warnings,
    COUNT(*) FILTER (WHERE status_omzet = 'ACHIEVED') as omzet_achieved,
    COUNT(*) FILTER (WHERE status_fokus = 'ACHIEVED') as fokus_achieved,
    ROUND(AVG(achievement_omzet_pct), 2) as avg_omzet_achievement,
    ROUND(AVG(achievement_fokus_pct), 2) as avg_fokus_achievement
FROM all_achievements
GROUP BY role
ORDER BY role;

-- ==========================================
-- SUMMARY
-- ==========================================
SELECT '=== SYSTEM STATUS ===' as summary;

SELECT 
    'Functions Created' as check_type,
    COUNT(*) as count
FROM information_schema.routines
WHERE routine_name IN (
    'get_time_gone_percentage',
    'calculate_target_achievement',
    'get_target_dashboard'
)
UNION ALL
SELECT 
    'Users with Targets' as check_type,
    COUNT(DISTINCT user_id) as count
FROM user_targets
UNION ALL
SELECT 
    'Active Periods' as check_type,
    COUNT(*) as count
FROM target_periods
WHERE deleted_at IS NULL;
