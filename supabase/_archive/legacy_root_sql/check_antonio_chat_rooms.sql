-- Check ANTONIO's chat rooms

-- 1. Check existing chat rooms for ANTONIO
SELECT '1. Chat rooms where ANTONIO is member:' as step;
SELECT 
    cr.id,
    cr.room_type,
    cr.name,
    s.store_name,
    cm.left_at
FROM chat_rooms cr
JOIN chat_members cm ON cm.room_id = cr.id
LEFT JOIN stores s ON s.id = cr.store_id
WHERE cm.user_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND cm.left_at IS NULL
ORDER BY cr.room_type, cr.name;

-- 2. Check chat rooms for ANTONIO's stores
SELECT '2. Chat rooms for ANTONIO assigned stores:' as step;
SELECT 
    cr.id,
    cr.room_type,
    cr.name,
    s.store_name,
    cr.is_active
FROM chat_rooms cr
JOIN stores s ON s.id = cr.store_id
WHERE s.id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND cr.room_type = 'toko'
ORDER BY s.store_name;

-- 3. Check if ANTONIO is member of his store rooms
SELECT '3. ANTONIO membership in his store rooms:' as step;
SELECT 
    s.store_name,
    cr.id as room_id,
    cr.name as room_name,
    CASE 
        WHEN cm.user_id IS NOT NULL THEN 'YES'
        ELSE 'NO'
    END as is_member
FROM stores s
JOIN assignments_sator_store ass ON ass.store_id = s.id
LEFT JOIN chat_rooms cr ON cr.store_id = s.id AND cr.room_type = 'toko'
LEFT JOIN chat_members cm ON cm.room_id = cr.id 
    AND cm.user_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND cm.left_at IS NULL
WHERE ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND ass.active = true
ORDER BY s.store_name;

-- 4. Count summary
SELECT '4. Summary:' as step;
SELECT 
    (SELECT COUNT(*) FROM assignments_sator_store 
     WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
     AND active = true) as antonio_stores,
    (SELECT COUNT(*) FROM chat_rooms cr
     WHERE cr.store_id IN (
         SELECT store_id FROM assignments_sator_store 
         WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
         AND active = true
     )
     AND cr.room_type = 'toko') as store_chat_rooms,
    (SELECT COUNT(*) FROM chat_members cm
     JOIN chat_rooms cr ON cr.id = cm.room_id
     WHERE cm.user_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
     AND cm.left_at IS NULL
     AND cr.room_type = 'toko') as antonio_toko_memberships;
