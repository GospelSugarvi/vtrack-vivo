-- Debug why get_sator_tim_detail returns empty

-- 1. Check ANTONIO exists
SELECT '1. ANTONIO user check:' as step;
SELECT id, full_name, email, role FROM users WHERE email = 'antonio@sator.vivo';

-- 2. Check assignments_sator_store for ANTONIO
SELECT '2. ANTONIO store assignments:' as step;
SELECT 
    ass.sator_id,
    ass.store_id,
    ass.active,
    s.store_name,
    s.deleted_at as store_deleted
FROM assignments_sator_store ass
LEFT JOIN stores s ON s.id = ass.store_id
WHERE ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo');

-- 3. Check stores table
SELECT '3. Stores check (not deleted):' as step;
SELECT COUNT(*) as total_stores FROM stores WHERE deleted_at IS NULL;

-- 4. Manual query to see what function should return
SELECT '4. Manual query (what function should return):' as step;
SELECT 
    s.id as store_id,
    s.store_name,
    s.area,
    s.deleted_at
FROM stores s
INNER JOIN assignments_sator_store ass 
    ON ass.store_id = s.id 
    AND ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND ass.active = true
WHERE s.deleted_at IS NULL;

-- 5. Check if there's a date issue
SELECT '5. Current date check:' as step;
SELECT CURRENT_DATE as today;

-- 6. Try calling function with explicit date
SELECT '6. Call function with explicit date:' as step;
SELECT get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
    '2026-01-31'::date
);

-- 7. Try calling function with NULL date (uses default)
SELECT '7. Call function with default date:' as step;
SELECT get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
);
