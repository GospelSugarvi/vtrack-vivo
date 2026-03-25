-- Check and fix chat_rooms table structure
DO $$
BEGIN
    -- Add sator_id column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'chat_rooms' AND column_name = 'sator_id'
    ) THEN
        ALTER TABLE chat_rooms ADD COLUMN sator_id UUID;
        RAISE NOTICE 'Added sator_id column to chat_rooms';
    END IF;
END $$;

-- Drop and recreate get_user_chat_rooms function
DROP FUNCTION IF EXISTS get_user_chat_rooms(UUID);

CREATE OR REPLACE FUNCTION get_user_chat_rooms(p_user_id UUID)
RETURNS TABLE (
    room_id UUID,
    room_type VARCHAR(20),
    room_name VARCHAR(255),
    room_description TEXT,
    store_id UUID,
    sator_id UUID,
    user1_id UUID,
    user2_id UUID,
    is_muted BOOLEAN,
    last_read_at TIMESTAMP WITH TIME ZONE,
    unread_count BIGINT,
    last_message_content TEXT,
    last_message_time TIMESTAMP WITH TIME ZONE,
    last_message_sender_name VARCHAR(255),
    member_count BIGINT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cr.id as room_id,
        cr.room_type,
        cr.name as room_name,
        cr.description as room_description,
        cr.store_id,
        cr.sator_id,
        cr.user1_id,
        cr.user2_id,
        COALESCE(cm.is_muted, FALSE) as is_muted,
        cm.last_read_at,
        
        COALESCE((
            SELECT COUNT(*)::BIGINT
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.created_at > COALESCE(cm.last_read_at, '1970-01-01'::TIMESTAMP WITH TIME ZONE)
            AND COALESCE(msg.is_deleted, FALSE) = FALSE
            AND msg.sender_id != p_user_id
        ), 0) as unread_count,
        
        (
            SELECT content
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND COALESCE(msg.is_deleted, FALSE) = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_content,
        
        (
            SELECT created_at
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND COALESCE(msg.is_deleted, FALSE) = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_time,
        
        (
            SELECT COALESCE(u.full_name, 'Unknown User')
            FROM chat_messages msg
            LEFT JOIN users u ON u.id = msg.sender_id
            WHERE msg.room_id = cr.id
            AND COALESCE(msg.is_deleted, FALSE) = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_sender_name,
        
        (
            SELECT COUNT(*)::BIGINT
            FROM chat_members mem
            WHERE mem.room_id = cr.id
            AND mem.left_at IS NULL
        ) as member_count,
        
        cr.created_at
        
    FROM chat_rooms cr
    LEFT JOIN chat_members cm ON cm.room_id = cr.id AND cm.user_id = p_user_id
    WHERE COALESCE(cr.is_active, TRUE) = TRUE
    AND (cm.user_id IS NOT NULL OR cr.room_type IN ('global', 'announcement'))
    ORDER BY 
        CASE WHEN unread_count > 0 THEN 0 ELSE 1 END,
        last_message_time DESC NULLS LAST,
        cr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_chat_rooms(UUID) TO authenticated;

SELECT 'Chat tables and functions fixed!' as result;