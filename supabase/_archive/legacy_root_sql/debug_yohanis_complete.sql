-- ==========================================
-- COMPLETE DEBUG FOR YOHANIS TARGET
-- Run this once to see all results
-- ==========================================

DO $$
DECLARE
    v_user_id UUID;
    v_period_id UUID;
    v_user_count INTEGER;
    v_target_count INTEGER;
    v_fokus_count INTEGER;
    v_view_count INTEGER;
BEGIN
    -- Get Yohanis user ID
    SELECT id INTO v_user_id
    FROM users
    WHERE full_name ILIKE '%yohanis%tipnoni%'
    LIMIT 1;
    
    -- Get Januari 2026 period ID
    SELECT id INTO v_period_id
    FROM target_periods
    WHERE period_name = 'Januari 2026'
    LIMIT 1;
    
    -- Count records
    SELECT COUNT(*) INTO v_user_count FROM users WHERE id = v_user_id;
    SELECT COUNT(*) INTO v_target_count FROM user_targets WHERE user_id = v_user_id;
    SELECT COUNT(*) INTO v_fokus_count FROM fokus_targets WHERE user_id = v_user_id;
    SELECT COUNT(*) INTO v_view_count FROM v_target_dashboard WHERE user_id = v_user_id;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'YOHANIS TARGET DEBUG SUMMARY';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'User ID: %', v_user_id;
    RAISE NOTICE 'Period ID: %', v_period_id;
    RAISE NOTICE 'User found: %', v_user_count;
    RAISE NOTICE 'Targets found: %', v_target_count;
    RAISE NOTICE 'Fokus targets found: %', v_fokus_count;
    RAISE NOTICE 'View records: %', v_view_count;
    RAISE NOTICE '========================================';
    
    -- Refresh view
    REFRESH MATERIALIZED VIEW v_target_dashboard;
    RAISE NOTICE 'Materialized view refreshed!';
    RAISE NOTICE '========================================';
END $$;

-- Show all data in one result set
SELECT 
    '1. USER INFO' as section,
    u.id::text as id,
    u.email as detail1,
    u.full_name as detail2,
    u.role as detail3,
    NULL::numeric as detail4,
    NULL::text as detail5
FROM users u
WHERE u.full_name ILIKE '%yohanis%tipnoni%'

UNION ALL

SELECT 
    '2. USER TARGETS' as section,
    ut.user_id::text as id,
    tp.period_name as detail1,
    ut.target_omzet::text as detail2,
    ut.target_fokus_total::text as detail3,
    NULL::numeric as detail4,
    NULL::text as detail5
FROM user_targets ut
JOIN target_periods tp ON ut.period_id = tp.id
JOIN users u ON ut.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%'

UNION ALL

SELECT 
    '3. FOKUS TARGETS' as section,
    ft.user_id::text as id,
    fb.bundle_name as detail1,
    ft.target_qty::text as detail2,
    tp.period_name as detail3,
    NULL::numeric as detail4,
    NULL::text as detail5
FROM fokus_targets ft
JOIN fokus_bundles fb ON ft.bundle_id = fb.id
JOIN target_periods tp ON ft.period_id = tp.id
JOIN users u ON ft.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%'

UNION ALL

SELECT 
    '4. DASHBOARD METRICS' as section,
    dpm.user_id::text as id,
    tp.period_name as detail1,
    dpm.total_omzet_real::text as detail2,
    dpm.total_units_focus::text as detail3,
    NULL::numeric as detail4,
    NULL::text as detail5
FROM dashboard_performance_metrics dpm
JOIN target_periods tp ON dpm.period_id = tp.id
JOIN users u ON dpm.user_id = u.id
WHERE u.full_name ILIKE '%tipnoni%'

UNION ALL

SELECT 
    '5. VIEW DATA' as section,
    vtd.user_id::text as id,
    vtd.period_name as detail1,
    vtd.target_omzet::text as detail2,
    vtd.actual_omzet::text as detail3,
    vtd.achievement_omzet_pct as detail4,
    vtd.status_omzet as detail5
FROM v_target_dashboard vtd
WHERE vtd.full_name ILIKE '%tipnoni%'
AND vtd.period_name = 'Januari 2026'

ORDER BY section;

-- Show detailed view data
SELECT 
    'DETAILED VIEW DATA' as info,
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
    warning_fokus
FROM v_target_dashboard
WHERE full_name ILIKE '%tipnoni%'
AND period_name = 'Januari 2026';
