-- Auto-add sator to chat room when assigned to store
-- This ensures sators automatically become members of their store chat rooms

-- Function to add sator to store chat room
CREATE OR REPLACE FUNCTION auto_add_sator_to_store_chat()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id uuid;
BEGIN
    -- Only process if assignment is active
    IF NEW.active = true THEN
        -- Find the toko chat room for this store
        SELECT id INTO v_room_id
        FROM chat_rooms
        WHERE store_id = NEW.store_id
        AND room_type = 'toko'
        AND is_active = true
        LIMIT 1;
        
        -- If chat room exists, add sator as member
        IF v_room_id IS NOT NULL THEN
            INSERT INTO chat_members (room_id, user_id, role, joined_at)
            VALUES (v_room_id, NEW.sator_id, 'member', NOW())
            ON CONFLICT (room_id, user_id) DO NOTHING;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on assignments_sator_store
DROP TRIGGER IF EXISTS trigger_auto_add_sator_to_chat ON assignments_sator_store;

CREATE TRIGGER trigger_auto_add_sator_to_chat
    AFTER INSERT OR UPDATE ON assignments_sator_store
    FOR EACH ROW
    EXECUTE FUNCTION auto_add_sator_to_store_chat();

-- Also handle when assignment is deactivated (remove from chat)
CREATE OR REPLACE FUNCTION auto_remove_sator_from_store_chat()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id uuid;
BEGIN
    -- Only process if assignment was deactivated
    IF OLD.active = true AND NEW.active = false THEN
        -- Find the toko chat room for this store
        SELECT id INTO v_room_id
        FROM chat_rooms
        WHERE store_id = NEW.store_id
        AND room_type = 'toko'
        AND is_active = true
        LIMIT 1;
        
        -- If chat room exists, mark sator as left
        IF v_room_id IS NOT NULL THEN
            UPDATE chat_members
            SET left_at = NOW()
            WHERE room_id = v_room_id
            AND user_id = NEW.sator_id
            AND left_at IS NULL;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for deactivation
DROP TRIGGER IF EXISTS trigger_auto_remove_sator_from_chat ON assignments_sator_store;

CREATE TRIGGER trigger_auto_remove_sator_from_chat
    AFTER UPDATE ON assignments_sator_store
    FOR EACH ROW
    WHEN (OLD.active = true AND NEW.active = false)
    EXECUTE FUNCTION auto_remove_sator_from_store_chat();

-- Test: Add ANDRI to his stores' chat rooms
SELECT 'Auto-adding ANDRI to his store chat rooms...' as status;

INSERT INTO chat_members (room_id, user_id, role, joined_at)
SELECT 
    cr.id as room_id,
    (SELECT id FROM users WHERE email = 'andri@sator.vivo') as user_id,
    'member' as role,
    NOW() as joined_at
FROM chat_rooms cr
WHERE cr.store_id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'andri@sator.vivo')
    AND active = true
)
AND cr.room_type = 'toko'
AND cr.is_active = true
AND NOT EXISTS (
    SELECT 1 
    FROM chat_members cm 
    WHERE cm.room_id = cr.id 
    AND cm.user_id = (SELECT id FROM users WHERE email = 'andri@sator.vivo')
    AND cm.left_at IS NULL
)
ON CONFLICT (room_id, user_id) DO NOTHING;

-- Verify
SELECT 'Verification - ANDRI chat rooms:' as step;
SELECT 
    (SELECT COUNT(*) FROM chat_members cm
     JOIN chat_rooms cr ON cr.id = cm.room_id
     WHERE cm.user_id = (SELECT id FROM users WHERE email = 'andri@sator.vivo')
     AND cm.left_at IS NULL
     AND cr.room_type = 'toko') as andri_toko_memberships,
    'Should be 11' as expected;

SELECT 'System ready! Future sator assignments will auto-add to chat rooms.' as status;
