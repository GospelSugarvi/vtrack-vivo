-- Simple debug without calling function

-- 1. Check ANTONIO exists
SELECT '1. ANTONIO user:' as step;
SELECT id, full_name, email FROM users WHERE email = 'antonio@sator.vivo';

-- 2. Check store assignments
SELECT '2. Store assignments count:' as step;
SELECT COUNT(*) as total 
FROM assignments_sator_store 
WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND active = true;

-- 3. List stores with details
SELECT '3. Stores assigned to ANTONIO:' as step;
SELECT 
    s.id,
    s.store_name,
    s.area,
    s.deleted_at,
    ass.active
FROM stores s
INNER JOIN assignments_sator_store ass 
    ON ass.store_id = s.id 
WHERE ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND ass.active = true
ORDER BY s.store_name;

-- 4. Check if stores have deleted_at NULL
SELECT '4. Stores NOT deleted:' as step;
SELECT 
    s.id,
    s.store_name,
    s.deleted_at
FROM stores s
INNER JOIN assignments_sator_store ass 
    ON ass.store_id = s.id 
WHERE ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND ass.active = true
AND s.deleted_at IS NULL
ORDER BY s.store_name;

-- 5. Check promotors in those stores
SELECT '5. Promotors in ANTONIO stores:' as step;
SELECT 
    u.full_name as promotor,
    s.store_name,
    aps.active as assignment_active
FROM users u
INNER JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
INNER JOIN stores s ON s.id = aps.store_id
WHERE s.id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND u.role = 'promotor'
AND u.deleted_at IS NULL
ORDER BY s.store_name, u.full_name;

-- 6. Now test function with explicit parameters
SELECT '6. Test function:' as step;
SELECT get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
    CURRENT_DATE
);
