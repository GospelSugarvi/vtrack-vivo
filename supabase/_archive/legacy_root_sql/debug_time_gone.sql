-- Debug Time-Gone Calculation
-- Expected: 23 Jan 2026 = 74.19% (23/31 days)

-- Step 1: Check CURRENT_DATE in database
SELECT 
    'Step 1: Check Current Date' as step,
    CURRENT_DATE as db_current_date,
    CURRENT_TIMESTAMP as db_current_timestamp;

-- Step 2: Manual calculation
SELECT 
    'Step 2: Manual Calculation' as step,
    '2026-01-01'::DATE as start_date,
    '2026-01-31'::DATE as end_date,
    '2026-01-23'::DATE as assumed_today,
    
    -- Total days
    ('2026-01-31'::DATE - '2026-01-01'::DATE + 1) as total_days,
    
    -- Days passed (if today is Jan 23)
    ('2026-01-23'::DATE - '2026-01-01'::DATE + 1) as days_passed,
    
    -- Expected percentage
    ROUND(
        (('2026-01-23'::DATE - '2026-01-01'::DATE + 1)::NUMERIC / 
        ('2026-01-31'::DATE - '2026-01-01'::DATE + 1)::NUMERIC) * 100,
        2
    ) as expected_pct;

-- Step 3: Check function logic
SELECT 
    'Step 3: Function Test' as step,
    id,
    period_name,
    start_date,
    end_date,
    CURRENT_DATE as today,
    (end_date - start_date + 1) as total_days,
    (CURRENT_DATE - start_date + 1) as days_passed_calc,
    get_time_gone_percentage(id) as function_result
FROM target_periods
WHERE period_name LIKE '%Januari%2026%'
AND deleted_at IS NULL;

-- Step 4: Check if timezone affects CURRENT_DATE
SELECT 
    'Step 4: Timezone Check' as step,
    CURRENT_DATE as current_date,
    CURRENT_DATE AT TIME ZONE 'Asia/Makassar' as current_date_wita,
    NOW() as now_utc,
    NOW() AT TIME ZONE 'Asia/Makassar' as now_wita;
