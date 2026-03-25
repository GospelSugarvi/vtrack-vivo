-- Check actual time-gone calculation result
-- Expected: 74.19% for Jan 23, 2026

SELECT 
    'Actual Function Result' as test,
    id,
    period_name,
    start_date,
    end_date,
    CURRENT_DATE as today,
    
    -- Manual calculation
    (end_date - start_date + 1) as total_days,
    (CURRENT_DATE - start_date + 1) as days_passed,
    ROUND(
        ((CURRENT_DATE - start_date + 1)::NUMERIC / 
        (end_date - start_date + 1)::NUMERIC) * 100,
        2
    ) as expected_pct,
    
    -- Function result
    get_time_gone_percentage(id) as function_pct
FROM target_periods
WHERE period_name LIKE '%Januari%2026%'
AND deleted_at IS NULL;
