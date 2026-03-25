-- Test leaderboard functions after bonus recalculation

-- ==========================================
-- TEST 1: Check if functions exist
-- ==========================================
SELECT 
    'Function Check' as test,
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('get_daily_ranking', 'get_live_feed');

-- ==========================================
-- TEST 2: Test get_daily_ranking with today's date
-- ==========================================
SELECT 'Daily Ranking Test' as test;

SELECT * FROM get_daily_ranking(CURRENT_DATE, NULL, 10);

-- ==========================================
-- TEST 3: Test get_live_feed
-- ==========================================
SELECT 'Live Feed Test' as test;

-- Get first promotor ID for testing
DO $$
DECLARE
    test_user_id UUID;
BEGIN
    SELECT id INTO test_user_id FROM users WHERE role = 'promotor' LIMIT 1;
    
    IF test_user_id IS NOT NULL THEN
        RAISE NOTICE 'Testing with user_id: %', test_user_id;
        PERFORM * FROM get_live_feed(test_user_id, CURRENT_DATE, 5, 0);
    ELSE
        RAISE NOTICE 'No promotor found for testing';
    END IF;
END $$;

-- ==========================================
-- TEST 4: Check sales data for today
-- ==========================================
SELECT 
    'Sales Data Check' as test,
    COUNT(*) as total_sales_today,
    SUM(estimated_bonus) as total_bonus_today,
    COUNT(DISTINCT promotor_id) as promotors_with_sales
FROM sales_sell_out
WHERE transaction_date = CURRENT_DATE;

-- ==========================================
-- TEST 5: Check if bonus values look correct
-- ==========================================
SELECT 
    'Bonus Distribution Check' as test,
    CASE 
        WHEN estimated_bonus = 0 THEN '0'
        WHEN estimated_bonus = 5000 THEN '5000 (OLD HARDCODED)'
        WHEN estimated_bonus < 25000 THEN '< 25k'
        WHEN estimated_bonus < 50000 THEN '25k-50k'
        WHEN estimated_bonus < 100000 THEN '50k-100k'
        ELSE '> 100k'
    END as bonus_range,
    COUNT(*) as count
FROM sales_sell_out
WHERE transaction_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY 
    CASE 
        WHEN estimated_bonus = 0 THEN '0'
        WHEN estimated_bonus = 5000 THEN '5000 (OLD HARDCODED)'
        WHEN estimated_bonus < 25000 THEN '< 25k'
        WHEN estimated_bonus < 50000 THEN '25k-50k'
        WHEN estimated_bonus < 100000 THEN '50k-100k'
        ELSE '> 100k'
    END
ORDER BY bonus_range;

-- ==========================================
-- TEST 6: Manual query to simulate get_daily_ranking
-- ==========================================
SELECT 
    'Manual Ranking Query' as test,
    u.full_name,
    s.store_name,
    COUNT(so.id) as sales_count,
    SUM(so.estimated_bonus) as total_bonus
FROM users u
JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
JOIN stores s ON s.id = aps.store_id
LEFT JOIN sales_sell_out so ON so.promotor_id = u.id AND so.transaction_date = CURRENT_DATE
WHERE u.role = 'promotor'
AND u.deleted_at IS NULL
GROUP BY u.id, u.full_name, s.store_name
ORDER BY total_bonus DESC NULLS LAST
LIMIT 10;
