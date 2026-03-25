-- Check all target periods
SELECT 
    id,
    period_name,
    start_date,
    end_date,
    CURRENT_DATE as today,
    deleted_at,
    
    -- Check if current date is in range
    CASE 
        WHEN CURRENT_DATE BETWEEN start_date AND end_date THEN '✅ ACTIVE'
        WHEN CURRENT_DATE < start_date THEN '⏳ FUTURE'
        WHEN CURRENT_DATE > end_date THEN '❌ PAST'
    END as status,
    
    -- Calculate time-gone
    (end_date - start_date + 1) as total_days,
    (CURRENT_DATE - start_date + 1) as days_passed,
    get_time_gone_percentage(id) as time_gone_pct
FROM target_periods
ORDER BY start_date DESC;
