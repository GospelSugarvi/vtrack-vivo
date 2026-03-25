-- =====================================================
-- FINAL FIX FOR CHAT SYSTEM
-- Date: 30 January 2026
-- Description: Consolidates all fixes: missing columns, type mismatches, and function names.
--              Addresses "column u.avatar_url does not exist" error.
-- =====================================================

-- 1. DROP ALL EXISTING CHAT FUNCTIONS TO CLEAN SLATE
DROP FUNCTION IF EXISTS get_user_chat_rooms(UUID);
DROP FUNCTION IF EXISTS get_chat_messages(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS get_chat_messages(UUID, UUID, INTEGER, INTEGER); -- Drop version with 4 args if exists
DROP FUNCTION IF EXISTS send_chat_message(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS send_message(UUID, UUID, VARCHAR, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID);
DROP FUNCTION IF EXISTS mark_messages_as_read(UUID);
DROP FUNCTION IF EXISTS mark_messages_read(UUID, UUID, UUID);
DROP FUNCTION IF EXISTS get_or_create_private_room(UUID);
DROP FUNCTION IF EXISTS is_room_member(UUID, UUID);

-- =====================================================
-- 2. GET USER CHAT ROOMS
-- Matches Flutter ChatRoom.fromJson
-- =====================================================
CREATE OR REPLACE FUNCTION get_user_chat_rooms(p_user_id UUID)
RETURNS TABLE (
    room_id UUID,
    id UUID, -- Alias for id
    room_type VARCHAR(20),
    room_name VARCHAR(255),
    name VARCHAR(255), -- Alias for name
    room_description TEXT,
    description TEXT, -- Alias for description
    store_id UUID,
    sator_id UUID,
    user1_id UUID,
    user2_id UUID,
    is_muted BOOLEAN,
    last_read_at TIMESTAMPTZ,
    unread_count BIGINT,
    last_message_content TEXT,
    last_message_time TIMESTAMPTZ,
    last_message_sender_name VARCHAR(255),
    member_count BIGINT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cr.id as room_id,
        cr.id, -- Alias
        cr.room_type,
        cr.name as room_name,
        cr.name, -- Alias
        cr.description as room_description,
        cr.description, -- Alias
        cr.store_id,
        cr.sator_id,
        cr.user1_id,
        cr.user2_id,
        COALESCE(cm.is_muted, FALSE) as is_muted,
        cm.last_read_at,
        
        -- Count unread messages
        COALESCE((
            SELECT COUNT(*)::BIGINT
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.created_at > COALESCE(cm.last_read_at, '1970-01-01'::TIMESTAMPTZ)
            AND msg.is_deleted = FALSE
            AND msg.sender_id != p_user_id
        ), 0) as unread_count,
        
        -- Last message info
        (
            SELECT content
            FROM chat_messages msg
            WHERE msg.room_id = cr.id AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC LIMIT 1
        ) as last_message_content,
        
        (
            SELECT created_at
            FROM chat_messages msg
            WHERE msg.room_id = cr.id AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC LIMIT 1
        ) as last_message_time,
        
        (
            SELECT COALESCE(u.full_name, 'Unknown User')
            FROM chat_messages msg
            LEFT JOIN users u ON u.id = msg.sender_id
            WHERE msg.room_id = cr.id AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC LIMIT 1
        ) as last_message_sender_name,
        
        -- Member count
        (
            SELECT COUNT(*)::BIGINT
            FROM chat_members mem
            WHERE mem.room_id = cr.id AND mem.left_at IS NULL
        ) as member_count,
        
        cr.created_at
        
    FROM chat_rooms cr
    JOIN chat_members cm ON cm.room_id = cr.id AND cm.user_id = p_user_id
    WHERE cr.is_active = TRUE
    AND cm.left_at IS NULL
    ORDER BY last_message_time DESC NULLS LAST, cr.created_at DESC;
END;
$$;

-- =====================================================
-- 3. GET CHAT MESSAGES
-- Matches Flutter ChatMessage.fromJson
-- REMOVED avatar_url to fix error 42703
-- =====================================================
CREATE OR REPLACE FUNCTION get_chat_messages(
    p_room_id UUID,
    p_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    message_id UUID,
    id UUID, -- Alias
    sender_id UUID,
    sender_name VARCHAR(255),
    sender_role VARCHAR(50),
    message_type VARCHAR(20),
    content TEXT,
    image_url TEXT,
    image_width INTEGER,
    image_height INTEGER,
    mentions UUID[],
    reply_to_id UUID,
    reply_to_content TEXT,
    reply_to_sender_name VARCHAR(255),
    is_edited BOOLEAN,
    edited_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    read_by_count BIGINT,
    reactions JSONB,
    is_own_message BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        msg.id as message_id,
        msg.id, -- Alias
        msg.sender_id,
        COALESCE(u.full_name, 'Unknown User') as sender_name,
        COALESCE(u.role, 'user') as sender_role,
        msg.message_type,
        msg.content,
        msg.image_url,
        msg.image_width,
        msg.image_height,
        msg.mentions,
        msg.reply_to_id,
        
        -- Reply info
        reply_msg.content as reply_to_content,
        COALESCE(reply_user.full_name, 'Unknown User') as reply_to_sender_name,
        
        COALESCE(msg.is_edited, FALSE),
        msg.edited_at,
        msg.created_at,
        
        -- Read count
        COALESCE((
            SELECT COUNT(*)::BIGINT FROM message_reads mr WHERE mr.message_id = msg.id
        ), 0) as read_by_count,
        
        -- Empty reactions (placeholder)
        '{}'::jsonb as reactions,
        
        (msg.sender_id = p_user_id) as is_own_message
        
    FROM chat_messages msg
    LEFT JOIN users u ON u.id = msg.sender_id
    LEFT JOIN chat_messages reply_msg ON reply_msg.id = msg.reply_to_id
    LEFT JOIN users reply_user ON reply_user.id = reply_msg.sender_id
    WHERE msg.room_id = p_room_id
    AND msg.is_deleted = FALSE
    ORDER BY msg.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- Alias for compatibility if needed (some callers might use 3 args)
CREATE OR REPLACE FUNCTION get_chat_messages(p_room_id UUID, p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
RETURNS TABLE (
    message_id UUID, id UUID, sender_id UUID, sender_name VARCHAR(255), sender_role VARCHAR(50),
    message_type VARCHAR(20), content TEXT, image_url TEXT, image_width INTEGER, image_height INTEGER,
    mentions UUID[], reply_to_id UUID, reply_to_content TEXT, reply_to_sender_name VARCHAR(255),
    is_edited BOOLEAN, edited_at TIMESTAMPTZ, created_at TIMESTAMPTZ,
    read_by_count BIGINT, reactions JSONB, is_own_message BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN QUERY SELECT * FROM get_chat_messages(p_room_id, auth.uid(), p_limit, p_offset);
END;
$$;


-- =====================================================
-- 4. SEND MESSAGE (Matches Flutter "send_message")
-- =====================================================
CREATE OR REPLACE FUNCTION send_message(
    p_room_id UUID,
    p_sender_id UUID,
    p_message_type VARCHAR(20) DEFAULT 'text',
    p_content TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL, -- Flutter might pass this name
    p_mentions UUID[] DEFAULT NULL,
    p_reply_to_id UUID DEFAULT NULL,
    p_image_width INTEGER DEFAULT NULL,
    p_image_height INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_message_id UUID;
BEGIN
    -- Validation
    IF p_message_type = 'text' AND (p_content IS NULL OR LENGTH(TRIM(p_content)) = 0) THEN
        RAISE EXCEPTION 'Text messages must have content';
    END IF;
    
    INSERT INTO chat_messages (
        room_id, sender_id, message_type, content, image_url,
        image_width, image_height, mentions, reply_to_id
    ) VALUES (
        p_room_id, p_sender_id, p_message_type, p_content, p_image_url,
        p_image_width, p_image_height, p_mentions, p_reply_to_id
    ) RETURNING id INTO v_message_id;
    
    -- Update stats
    UPDATE chat_rooms SET updated_at = NOW() WHERE id = p_room_id;
    UPDATE chat_members SET last_read_at = NOW() WHERE room_id = p_room_id AND user_id = p_sender_id;
    
    RETURN v_message_id;
END;
$$;

-- Alias for Flutter calls that might still use old RPC name or params
-- Note: Flutter code uses 'send_message' with: p_room_id, p_sender_id, p_message_type, p_content, p_mentions, p_reply_to_id
-- And another call for image with: p_image_url, etc.
-- The function above covers both cases (default nulls).

-- =====================================================
-- 5. MARK MESSAGES READ
-- =====================================================
CREATE OR REPLACE FUNCTION mark_messages_read(
    p_room_id UUID,
    p_user_id UUID,
    p_up_to_message_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE chat_members SET last_read_at = NOW() WHERE room_id = p_room_id AND user_id = p_user_id;
    
    INSERT INTO message_reads (message_id, user_id)
    SELECT id, p_user_id FROM chat_messages
    WHERE room_id = p_room_id AND sender_id != p_user_id AND is_deleted = FALSE
    ON CONFLICT DO NOTHING;
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- =====================================================
-- PERMISSIONS
-- =====================================================
GRANT EXECUTE ON FUNCTION get_user_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_messages(UUID, UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_messages(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION send_message(UUID, UUID, VARCHAR, TEXT, TEXT, UUID[], UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_messages_read(UUID, UUID, UUID) TO authenticated;
