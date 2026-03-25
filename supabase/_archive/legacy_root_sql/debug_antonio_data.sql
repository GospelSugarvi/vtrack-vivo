-- Debug ANTONIO's data to see what should appear

-- 1. Get ANTONIO's user ID
SELECT 'ANTONIO User ID:' as info;
SELECT id, full_name, email, role FROM users WHERE email = 'antonio@sator.vivo';

-- 2. Check stores assigned to ANTONIO
SELECT 'Stores assigned to ANTONIO (should be 16):' as info;
SELECT COUNT(*) as total_stores FROM assignments_sator_store 
WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND active = true;

-- 3. List all ANTONIO's stores
SELECT 'List of ANTONIO stores:' as info;
SELECT s.store_name, s.area 
FROM stores s
JOIN assignments_sator_store ass ON ass.store_id = s.id
WHERE ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND ass.active = true
ORDER BY s.store_name;

-- 4. Check promotors in ANTONIO's stores
SELECT 'Promotors in ANTONIO stores:' as info;
SELECT DISTINCT
    u.full_name as promotor_name,
    s.store_name
FROM users u
JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
JOIN stores s ON s.id = aps.store_id
WHERE s.id IN (
    SELECT store_id FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND u.role = 'promotor'
ORDER BY s.store_name, u.full_name;

-- 5. Test get_sator_tim_detail function
SELECT 'get_sator_tim_detail result:' as info;
SELECT * FROM get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
);

-- 6. Check if function exists and is correct
SELECT 'Function definition check:' as info;
SELECT 
    routine_name,
    routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'get_sator_tim_detail';
