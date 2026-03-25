-- Test Bulk Target System Fix
-- Run this to verify the fix works correctly

-- ==========================================
-- TEST 1: Check if hierarchy tables exist
-- ==========================================
SELECT 'TEST 1: Checking hierarchy tables...' as test;

SELECT 
    'hierarchy_sator_promotor' as table_name,
    COUNT(*) as record_count
FROM hierarchy_sator_promotor
UNION ALL
SELECT 
    'hierarchy_spv_sator' as table_name,
    COUNT(*) as record_count
FROM hierarchy_spv_sator;

-- ==========================================
-- TEST 2: Check if user_targets columns exist
-- ==========================================
SELECT 'TEST 2: Checking user_targets columns...' as test;

SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'user_targets'
ORDER BY ordinal_position;

-- ==========================================
-- TEST 3: Test get_users_with_hierarchy function
-- ==========================================
SELECT 'TEST 3: Testing get_users_with_hierarchy for promotor...' as test;

SELECT 
    user_id,
    full_name,
    sator_name,
    target_omzet,
    target_fokus_total,
    has_target
FROM get_users_with_hierarchy(
    (SELECT id FROM target_periods WHERE extract(month from start_date) = extract(month from current_date) LIMIT 1),
    'promotor'
)
LIMIT 5;

-- ==========================================
-- TEST 4: Test bulk_set_targets function
-- ==========================================
SELECT 'TEST 4: Testing bulk_set_targets function...' as test;

-- Get first promotor for testing
DO $$
DECLARE
    v_test_user_id UUID;
    v_period_id UUID;
    v_result INTEGER;
BEGIN
    -- Get current period
    SELECT id INTO v_period_id 
    FROM target_periods 
    WHERE extract(month from start_date) = extract(month from current_date)
    LIMIT 1;
    
    -- Get first promotor
    SELECT id INTO v_test_user_id 
    FROM users 
    WHERE role = 'promotor' 
    AND deleted_at IS NULL 
    LIMIT 1;
    
    IF v_test_user_id IS NOT NULL AND v_period_id IS NOT NULL THEN
        -- Test bulk set
        SELECT bulk_set_targets(
            ARRAY[v_test_user_id],
            v_period_id,
            150000000,  -- target_omzet
            30          -- target_fokus_total
        ) INTO v_result;
        
        RAISE NOTICE 'Bulk set result: % user(s) updated', v_result;
        
        -- Verify the target was set
        RAISE NOTICE 'Verifying target...';
        PERFORM 1 FROM user_targets 
        WHERE user_id = v_test_user_id 
        AND period_id = v_period_id
        AND target_omzet = 150000000;
        
        IF FOUND THEN
            RAISE NOTICE '✅ Target successfully set!';
        ELSE
            RAISE NOTICE '❌ Target not found!';
        END IF;
    ELSE
        RAISE NOTICE '⚠️ No test data available (need promotor and period)';
    END IF;
END $$;

-- ==========================================
-- TEST 5: Check function permissions
-- ==========================================
SELECT 'TEST 5: Checking function permissions...' as test;

SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_name IN ('bulk_set_targets', 'get_users_with_hierarchy')
ORDER BY routine_name;

-- ==========================================
-- SUMMARY
-- ==========================================
SELECT '✅ All tests completed!' as summary;
SELECT 'If no errors above, the fix is working correctly.' as note;
