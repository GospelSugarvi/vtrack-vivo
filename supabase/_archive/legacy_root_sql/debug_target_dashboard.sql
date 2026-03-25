-- Debug Target Dashboard
-- Check why target is not showing for promotor

-- ==========================================
-- STEP 1: Check if period exists
-- ==========================================
SELECT 
    '1. Check Periods' as step,
    id,
    period_name,
    start_date,
    end_date,
    target_month,
    target_year,
    CASE 
        WHEN CURRENT_DATE BETWEEN start_date AND end_date THEN '✅ ACTIVE'
        ELSE '❌ NOT ACTIVE'
    END as status
FROM target_periods
WHERE deleted_at IS NULL
ORDER BY start_date DESC;

-- ==========================================
-- STEP 2: Check if user_targets exists
-- ==========================================
SELECT 
    '2. Check User Targets' as step,
    ut.id,
    u.full_name,
    tp.period_name,
    ut.target_sell_out,
    ut.target_fokus
FROM user_targets ut
JOIN users u ON u.id = ut.user_id
JOIN target_periods tp ON tp.id = ut.period_id
WHERE u.role = 'promotor'
ORDER BY u.full_name;

-- ==========================================
-- STEP 3: Check dashboard_performance_metrics
-- ==========================================
SELECT 
    '3. Check Performance Metrics' as step,
    dpm.id,
    u.full_name,
    tp.period_name,
    dpm.total_omzet_real,
    dpm.total_units_focus
FROM dashboard_performance_metrics dpm
JOIN users u ON u.id = dpm.user_id
JOIN target_periods tp ON tp.id = dpm.period_id
WHERE u.role = 'promotor'
ORDER BY u.full_name;

-- ==========================================
-- STEP 4: Test get_target_dashboard function
-- ==========================================
SELECT 
    '4. Test Function' as step,
    *
FROM get_target_dashboard(
    (SELECT id FROM users WHERE role = 'promotor' LIMIT 1),
    NULL -- current period
);

-- ==========================================
-- STEP 5: Check current month/year
-- ==========================================
SELECT 
    '5. Current Date Info' as step,
    CURRENT_DATE as today,
    EXTRACT(MONTH FROM CURRENT_DATE) as current_month,
    EXTRACT(YEAR FROM CURRENT_DATE) as current_year;

-- ==========================================
-- STEP 6: Check if period matches current month
-- ==========================================
SELECT 
    '6. Period Match Check' as step,
    id,
    period_name,
    target_month,
    target_year,
    EXTRACT(MONTH FROM CURRENT_DATE) as current_month,
    EXTRACT(YEAR FROM CURRENT_DATE) as current_year,
    CASE 
        WHEN target_month = EXTRACT(MONTH FROM CURRENT_DATE) 
        AND target_year = EXTRACT(YEAR FROM CURRENT_DATE) 
        THEN '✅ MATCH'
        ELSE '❌ NO MATCH'
    END as match_status
FROM target_periods
WHERE deleted_at IS NULL;
