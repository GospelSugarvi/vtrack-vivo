-- Test Time-Gone Calculation
-- Current Date: 23 Januari 2026

-- Manual calculation test
SELECT 
    'Manual Test' as test_type,
    '2026-01-01'::DATE as start_date,
    '2026-01-31'::DATE as end_date,
    CURRENT_DATE as today,
    
    -- Total days in period
    ('2026-01-31'::DATE - '2026-01-01'::DATE + 1) as total_days,
    
    -- Days passed
    (CURRENT_DATE - '2026-01-01'::DATE + 1) as days_passed,
    
    -- Percentage
    ROUND(
        ((CURRENT_DATE - '2026-01-01'::DATE + 1)::NUMERIC / 
        ('2026-01-31'::DATE - '2026-01-01'::DATE + 1)::NUMERIC) * 100,
        2
    ) as time_gone_pct_manual;

-- Test with actual periods
SELECT 
    'Database Test' as test_type,
    period_name,
    start_date,
    end_date,
    CURRENT_DATE as today,
    (end_date - start_date + 1) as total_days,
    (CURRENT_DATE - start_date + 1) as days_passed,
    get_time_gone_percentage(id) as time_gone_pct_function
FROM target_periods
WHERE deleted_at IS NULL
ORDER BY start_date DESC;

-- Expected for Jan 23, 2026:
-- Days passed: 23 (from Jan 1 to Jan 23)
-- Total days: 31 (Jan 1 to Jan 31)
-- Percentage: 23/31 * 100 = 74.19%
