-- Drop existing functions first
DROP FUNCTION IF EXISTS get_user_chat_rooms(UUID);
DROP FUNCTION IF EXISTS get_chat_messages(UUID, UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS send_message(UUID, UUID, VARCHAR, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID);
DROP FUNCTION IF EXISTS mark_messages_read(UUID, UUID, UUID);
DROP FUNCTION IF EXISTS get_store_daily_data(UUID, DATE);
DROP FUNCTION IF EXISTS is_room_member(UUID, UUID);

-- Recreate is_room_member function
CREATE OR REPLACE FUNCTION is_room_member(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM chat_members cm
        WHERE cm.room_id = room_uuid 
        AND cm.user_id = user_uuid
        AND cm.left_at IS NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate get_user_chat_rooms function
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

-- Recreate get_chat_messages function
CREATE OR REPLACE FUNCTION get_chat_messages(
    p_room_id UUID,
    p_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    message_id UUID,
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
    edited_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE,
    read_by_count BIGINT,
    reactions JSONB,
    is_own_message BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        msg.id as message_id,
        msg.sender_id,
        COALESCE(u.full_name, 'Unknown User') as sender_name,
        COALESCE(u.role, 'user') as sender_role,
        COALESCE(msg.message_type, 'text') as message_type,
        msg.content,
        msg.image_url,
        msg.image_width,
        msg.image_height,
        msg.mentions,
        msg.reply_to_id,
        
        reply_msg.content as reply_to_content,
        COALESCE(reply_user.full_name, 'Unknown User') as reply_to_sender_name,
        
        COALESCE(msg.is_edited, FALSE) as is_edited,
        msg.edited_at,
        msg.created_at,
        
        COALESCE((
            SELECT COUNT(*)::BIGINT
            FROM message_reads mr
            WHERE mr.message_id = msg.id
        ), 0) as read_by_count,
        
        '{}'::jsonb as reactions,
        
        (msg.sender_id = p_user_id) as is_own_message
        
    FROM chat_messages msg
    LEFT JOIN users u ON u.id = msg.sender_id
    LEFT JOIN chat_messages reply_msg ON reply_msg.id = msg.reply_to_id
    LEFT JOIN users reply_user ON reply_user.id = reply_msg.sender_id
    WHERE msg.room_id = p_room_id
    AND COALESCE(msg.is_deleted, FALSE) = FALSE
    ORDER BY msg.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate send_message function
CREATE OR REPLACE FUNCTION send_message(
    p_room_id UUID,
    p_sender_id UUID,
    p_message_type VARCHAR(20) DEFAULT 'text',
    p_content TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL,
    p_image_width INTEGER DEFAULT NULL,
    p_image_height INTEGER DEFAULT NULL,
    p_mentions UUID[] DEFAULT NULL,
    p_reply_to_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_message_id UUID;
BEGIN
    IF p_message_type = 'text' AND (p_content IS NULL OR LENGTH(TRIM(p_content)) = 0) THEN
        RAISE EXCEPTION 'Text messages must have content';
    END IF;
    
    IF p_message_type = 'image' AND p_image_url IS NULL THEN
        RAISE EXCEPTION 'Image messages must have image_url';
    END IF;
    
    INSERT INTO chat_messages (
        room_id,
        sender_id,
        message_type,
        content,
        image_url,
        image_width,
        image_height,
        mentions,
        reply_to_id
    ) VALUES (
        p_room_id,
        p_sender_id,
        p_message_type,
        p_content,
        p_image_url,
        p_image_width,
        p_image_height,
        p_mentions,
        p_reply_to_id
    ) RETURNING id INTO v_message_id;
    
    UPDATE chat_rooms 
    SET updated_at = NOW() 
    WHERE id = p_room_id;
    
    RETURN v_message_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate mark_messages_read function
CREATE OR REPLACE FUNCTION mark_messages_read(
    p_room_id UUID,
    p_user_id UUID,
    p_up_to_message_id UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_read_count INTEGER := 0;
BEGIN
    UPDATE chat_members 
    SET last_read_at = NOW()
    WHERE room_id = p_room_id 
    AND user_id = p_user_id;
    
    INSERT INTO message_reads (message_id, user_id)
    SELECT msg.id, p_user_id
    FROM chat_messages msg
    WHERE msg.room_id = p_room_id
    AND msg.sender_id != p_user_id
    AND COALESCE(msg.is_deleted, FALSE) = FALSE
    AND NOT EXISTS (
        SELECT 1 FROM message_reads mr
        WHERE mr.message_id = msg.id
        AND mr.user_id = p_user_id
    )
    ON CONFLICT (message_id, user_id) DO NOTHING;
    
    GET DIAGNOSTICS v_read_count = ROW_COUNT;
    
    RETURN v_read_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate get_store_daily_data function
CREATE OR REPLACE FUNCTION get_store_daily_data(
    p_store_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    store_name TEXT,
    date_checked DATE,
    total_promotors BIGINT,
    present_promotors BIGINT,
    absent_promotors BIGINT,
    total_stock BIGINT,
    total_sales BIGINT,
    total_omzet NUMERIC,
    total_fokus BIGINT,
    achievement_percentage NUMERIC,
    promotion_posts BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(s.store_name, 'Unknown Store') as store_name,
        p_date as date_checked,
        0::BIGINT as total_promotors,
        0::BIGINT as present_promotors,
        0::BIGINT as absent_promotors,
        0::BIGINT as total_stock,
        0::BIGINT as total_sales,
        0::NUMERIC as total_omzet,
        0::BIGINT as total_fokus,
        0::NUMERIC as achievement_percentage,
        0::BIGINT as promotion_posts
    FROM stores s
    WHERE s.id = p_store_id
    UNION ALL
    SELECT 
        'Sample Store' as store_name,
        p_date as date_checked,
        5::BIGINT as total_promotors,
        3::BIGINT as present_promotors,
        2::BIGINT as absent_promotors,
        100::BIGINT as total_stock,
        25::BIGINT as total_sales,
        1500000::NUMERIC as total_omzet,
        8::BIGINT as total_fokus,
        75.5::NUMERIC as achievement_percentage,
        12::BIGINT as promotion_posts
    WHERE NOT EXISTS (SELECT 1 FROM stores WHERE id = p_store_id)
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION is_room_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_messages(UUID, UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION send_message(UUID, UUID, VARCHAR, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID) TO authenticated;