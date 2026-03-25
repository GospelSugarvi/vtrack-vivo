-- Test Sator Store Assignment System
-- Run this to verify the system is working correctly

-- 1. Check if assignments_sator_store table exists and has data
SELECT 'assignments_sator_store table check:' as test;
SELECT 
    u.full_name as sator_name,
    u.email,
    COUNT(ass.store_id) as assigned_stores
FROM users u
LEFT JOIN assignments_sator_store ass ON ass.sator_id = u.id AND ass.active = true
WHERE u.role = 'sator'
GROUP BY u.id, u.full_name, u.email
ORDER BY u.full_name;

-- 2. Check ANTONIO's assigned stores (should be 16)
SELECT 'ANTONIO assigned stores:' as test;
SELECT 
    s.store_name,
    s.area,
    ass.created_at
FROM assignments_sator_store ass
JOIN stores s ON s.id = ass.store_id
JOIN users u ON u.id = ass.sator_id
WHERE u.email = 'antonio@sator.vivo'
AND ass.active = true
ORDER BY s.store_name;

-- 3. Check if functions exist
SELECT 'Functions check:' as test;
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN (
    'get_store_stock_status',
    'get_sator_daily_summary',
    'get_sator_kpi_summary',
    'get_sator_alerts',
    'get_sator_tim_detail'
)
ORDER BY routine_name;

-- 4. Test get_sator_tim_detail function for ANTONIO
SELECT 'get_sator_tim_detail test for ANTONIO:' as test;
SELECT * FROM get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
);

-- 5. Test get_store_stock_status function for ANTONIO
SELECT 'get_store_stock_status test for ANTONIO:' as test;
SELECT get_store_stock_status(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
);

-- 6. Check promotors in ANTONIO's stores
SELECT 'Promotors in ANTONIO stores:' as test;
SELECT DISTINCT
    u.full_name as promotor_name,
    u.email,
    s.store_name
FROM users u
JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
JOIN stores s ON s.id = aps.store_id
WHERE s.id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND u.role = 'promotor'
ORDER BY u.full_name, s.store_name;

-- 7. Summary
SELECT 'SUMMARY:' as test;
SELECT 
    'ANTONIO should see 16 stores and their promotors' as expected_result,
    (SELECT COUNT(*) FROM assignments_sator_store 
     WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
     AND active = true) as antonio_stores,
    (SELECT COUNT(DISTINCT aps.promotor_id)
     FROM assignments_promotor_store aps
     WHERE aps.store_id IN (
         SELECT store_id FROM assignments_sator_store 
         WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
         AND active = true
     )
     AND aps.active = true) as antonio_promotors;
