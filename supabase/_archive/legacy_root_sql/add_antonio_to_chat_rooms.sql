-- Add ANTONIO to all his store chat rooms

-- Insert ANTONIO as member in all his store chat rooms
INSERT INTO chat_members (room_id, user_id, role, joined_at)
SELECT 
    cr.id as room_id,
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo') as user_id,
    'member' as role,
    NOW() as joined_at
FROM chat_rooms cr
WHERE cr.store_id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND cr.room_type = 'toko'
AND cr.is_active = true
-- Only insert if not already a member
AND NOT EXISTS (
    SELECT 1 
    FROM chat_members cm 
    WHERE cm.room_id = cr.id 
    AND cm.user_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND cm.left_at IS NULL
)
ON CONFLICT (room_id, user_id) DO NOTHING;

-- Verify
SELECT 'Added ANTONIO to chat rooms!' as status;
SELECT 'Verification:' as step;
SELECT 
    (SELECT COUNT(*) FROM chat_members cm
     JOIN chat_rooms cr ON cr.id = cm.room_id
     WHERE cm.user_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
     AND cm.left_at IS NULL
     AND cr.room_type = 'toko') as antonio_toko_memberships,
    'Should be 16' as expected;

-- Show all ANTONIO's toko chat rooms
SELECT 'ANTONIO toko chat rooms:' as step;
SELECT 
    s.store_name,
    cr.name as room_name,
    cm.joined_at
FROM chat_members cm
JOIN chat_rooms cr ON cr.id = cm.room_id
JOIN stores s ON s.id = cr.store_id
WHERE cm.user_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND cm.left_at IS NULL
AND cr.room_type = 'toko'
ORDER BY s.store_name;
