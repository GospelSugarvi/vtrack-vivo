-- =============================================
-- CHAT SYSTEM CORE FUNCTIONS
-- Date: 27 January 2026
-- Description: Core functions for chat operations
-- =============================================

SET search_path = public;

-- =============================================
-- 1. GET USER CHAT ROOMS WITH UNREAD COUNTS
-- =============================================

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
        cm.is_muted,
        cm.last_read_at,
        
        -- Count unread messages
        COALESCE((
            SELECT COUNT(*)
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.created_at > COALESCE(cm.last_read_at, '1970-01-01'::TIMESTAMP WITH TIME ZONE)
            AND msg.is_deleted = FALSE
            AND msg.sender_id != p_user_id -- Don't count own messages
        ), 0) as unread_count,
        
        -- Get last message info
        (
            SELECT content
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_content,
        
        (
            SELECT created_at
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_time,
        
        (
            SELECT u.full_name
            FROM chat_messages msg
            JOIN users u ON u.id = msg.sender_id
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_sender_name,
        
        -- Count active members
        (
            SELECT COUNT(*)
            FROM chat_members mem
            WHERE mem.room_id = cr.id
            AND mem.left_at IS NULL
        ) as member_count,
        
        cr.created_at
        
    FROM chat_rooms cr
    JOIN chat_members cm ON cm.room_id = cr.id
    WHERE cm.user_id = p_user_id
    AND cm.left_at IS NULL
    AND cr.is_active = TRUE
    ORDER BY 
        -- Priority: unread messages first, then by last message time
        CASE WHEN unread_count > 0 THEN 0 ELSE 1 END,
        last_message_time DESC NULLS LAST,
        cr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 2. GET CHAT MESSAGES WITH PAGINATION
-- =============================================

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
    -- Check if user is member of the room
    IF NOT is_room_member(p_room_id, p_user_id) THEN
        RAISE EXCEPTION 'User is not a member of this room';
    END IF;

    RETURN QUERY
    SELECT 
        msg.id as message_id,
        msg.sender_id,
        u.full_name as sender_name,
        u.role as sender_role,
        msg.message_type,
        msg.content,
        msg.image_url,
        msg.image_width,
        msg.image_height,
        msg.mentions,
        msg.reply_to_id,
        
        -- Reply message content
        reply_msg.content as reply_to_content,
        reply_user.full_name as reply_to_sender_name,
        
        msg.is_edited,
        msg.edited_at,
        msg.created_at,
        
        -- Count how many people read this message
        (
            SELECT COUNT(*)
            FROM message_reads mr
            WHERE mr.message_id = msg.id
        ) as read_by_count,
        
        -- Get reactions as JSON
        (
            SELECT COALESCE(
                jsonb_object_agg(
                    emoji, 
                    jsonb_build_object(
                        'count', count,
                        'users', users
                    )
                ),
                '{}'::jsonb
            )
            FROM (
                SELECT 
                    emoji,
                    COUNT(*) as count,
                    jsonb_agg(
                        jsonb_build_object(
                            'user_id', user_id,
                            'name', u.full_name
                        )
                    ) as users
                FROM message_reactions mr
                JOIN users u ON u.id = mr.user_id
                WHERE mr.message_id = msg.id
                GROUP BY emoji
            ) reactions_data
        ) as reactions,
        
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
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- =============================================
-- 3. SEND MESSAGE FUNCTION
-- =============================================

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
    v_room_type VARCHAR(20);
    v_mentioned_user UUID;
BEGIN
    -- Check if user is member of the room
    IF NOT is_room_member(p_room_id, p_sender_id) THEN
        RAISE EXCEPTION 'User is not a member of this room';
    END IF;
    
    -- Get room type for special validation
    SELECT room_type INTO v_room_type
    FROM chat_rooms
    WHERE id = p_room_id;
    
    -- Check announcement room permissions
    IF v_room_type = 'announcement' THEN
        IF NOT EXISTS (
            SELECT 1 FROM users 
            WHERE id = p_sender_id 
            AND role IN ('spv', 'admin')
        ) THEN
            RAISE EXCEPTION 'Only SPV and Admin can post in announcement rooms';
        END IF;
    END IF;
    
    -- Validate content based on message type
    IF p_message_type = 'text' AND (p_content IS NULL OR LENGTH(TRIM(p_content)) = 0) THEN
        RAISE EXCEPTION 'Text messages must have content';
    END IF;
    
    IF p_message_type = 'image' AND p_image_url IS NULL THEN
        RAISE EXCEPTION 'Image messages must have image_url';
    END IF;
    
    -- Validate mentions are room members
    IF p_mentions IS NOT NULL THEN
        FOREACH v_mentioned_user IN ARRAY p_mentions
        LOOP
            IF NOT is_room_member(p_room_id, v_mentioned_user) THEN
                RAISE EXCEPTION 'Cannot mention user who is not a room member: %', v_mentioned_user;
            END IF;
        END LOOP;
    END IF;
    
    -- Insert the message
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
    
    -- Update room's updated_at timestamp
    UPDATE chat_rooms 
    SET updated_at = NOW() 
    WHERE id = p_room_id;
    
    RETURN v_message_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 4. MARK MESSAGES AS READ
-- =============================================

CREATE OR REPLACE FUNCTION mark_messages_read(
    p_room_id UUID,
    p_user_id UUID,
    p_up_to_message_id UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_read_count INTEGER := 0;
    v_message_record RECORD;
BEGIN
    -- Check if user is member of the room
    IF NOT is_room_member(p_room_id, p_user_id) THEN
        RAISE EXCEPTION 'User is not a member of this room';
    END IF;
    
    -- Update last_read_at in chat_members
    UPDATE chat_members 
    SET last_read_at = NOW()
    WHERE room_id = p_room_id 
    AND user_id = p_user_id;
    
    -- If specific message ID provided, mark up to that message
    IF p_up_to_message_id IS NOT NULL THEN
        -- Insert read receipts for unread messages up to the specified message
        INSERT INTO message_reads (message_id, user_id)
        SELECT msg.id, p_user_id
        FROM chat_messages msg
        WHERE msg.room_id = p_room_id
        AND msg.created_at <= (
            SELECT created_at 
            FROM chat_messages 
            WHERE id = p_up_to_message_id
        )
        AND msg.sender_id != p_user_id -- Don't mark own messages
        AND msg.is_deleted = FALSE
        AND NOT EXISTS (
            SELECT 1 FROM message_reads mr
            WHERE mr.message_id = msg.id
            AND mr.user_id = p_user_id
        );
    ELSE
        -- Mark all unread messages in the room as read
        INSERT INTO message_reads (message_id, user_id)
        SELECT msg.id, p_user_id
        FROM chat_messages msg
        WHERE msg.room_id = p_room_id
        AND msg.sender_id != p_user_id -- Don't mark own messages
        AND msg.is_deleted = FALSE
        AND NOT EXISTS (
            SELECT 1 FROM message_reads mr
            WHERE mr.message_id = msg.id
            AND mr.user_id = p_user_id
        );
    END IF;
    
    GET DIAGNOSTICS v_read_count = ROW_COUNT;
    
    RETURN v_read_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 5. GET STORE DAILY DATA FOR TOKO ROOMS
-- =============================================

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
        s.store_name,
        p_date as date_checked,
        
        -- Promotor counts
        (
            SELECT COUNT(*)
            FROM users u
            JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
            WHERE aps.store_id = p_store_id
            AND u.role = 'promotor'
            AND u.status = 'active'
            AND aps.active = TRUE
        ) as total_promotors,
        
        -- Present promotors (based on attendance or recent activity)
        (
            SELECT COUNT(DISTINCT u.id)
            FROM users u
            JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
            LEFT JOIN schedules sch ON sch.user_id = u.id
            WHERE aps.store_id = p_store_id
            AND u.role = 'promotor'
            AND u.status = 'active'
            AND aps.active = TRUE
            AND (
                (sch.date = p_date AND sch.status = 'present')
                OR u.updated_at::DATE = p_date
            )
        ) as present_promotors,
        
        -- Absent promotors
        (
            SELECT COUNT(*)
            FROM users u
            JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
            WHERE aps.store_id = p_store_id
            AND u.role = 'promotor'
            AND u.status = 'active'
            AND aps.active = TRUE
        ) - (
            SELECT COUNT(DISTINCT u.id)
            FROM users u
            JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
            LEFT JOIN schedules sch ON sch.user_id = u.id
            WHERE aps.store_id = p_store_id
            AND u.role = 'promotor'
            AND u.status = 'active'
            AND aps.active = TRUE
            AND (
                (sch.date = p_date AND sch.status = 'present')
                OR u.updated_at::DATE = p_date
            )
        ) as absent_promotors,
        
        -- Stock data
        COALESCE((
            SELECT SUM(quantity)
            FROM store_inventory si
            WHERE si.store_id = p_store_id
        ), 0) as total_stock,
        
        -- Sales data for the date
        COALESCE((
            SELECT COUNT(*)
            FROM sales_sell_out sso
            WHERE sso.store_id = p_store_id
            AND sso.transaction_date = p_date
        ), 0) as total_sales,
        
        COALESCE((
            SELECT SUM(sso.price_at_transaction)
            FROM sales_sell_out sso
            WHERE sso.store_id = p_store_id
            AND sso.transaction_date = p_date
        ), 0) as total_omzet,
        
        -- Fokus sales
        COALESCE((
            SELECT COUNT(*)
            FROM sales_sell_out sso
            JOIN product_variants pv ON pv.id = sso.variant_id
            JOIN products p ON p.id = pv.product_id
            WHERE sso.store_id = p_store_id
            AND sso.transaction_date = p_date
            AND p.is_focus = TRUE
        ), 0) as total_fokus,
        
        -- Achievement percentage (simplified)
        COALESCE((
            SELECT AVG(
                CASE 
                    WHEN ut.target_omzet > 0 THEN (dpm.total_omzet_real / ut.target_omzet * 100)
                    ELSE 0
                END
            )
            FROM dashboard_performance_metrics dpm
            JOIN users u ON u.id = dpm.user_id
            JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
            JOIN user_targets ut ON ut.user_id = u.id AND ut.period_id = dpm.period_id
            WHERE aps.store_id = p_store_id
            AND aps.active = TRUE
        ), 0) as achievement_percentage,
        
        -- Promotion posts (if promotion system exists)
        0 as promotion_posts -- Placeholder
        
    FROM stores s
    WHERE s.id = p_store_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 6. MESSAGE CLEANUP FUNCTION
-- =============================================

CREATE OR REPLACE FUNCTION cleanup_expired_messages()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER := 0;
BEGIN
    -- Delete expired messages and their related data
    WITH deleted_messages AS (
        DELETE FROM chat_messages
        WHERE expires_at IS NOT NULL
        AND expires_at < NOW()
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted_count FROM deleted_messages;
    
    -- Clean up orphaned read receipts and reactions
    -- (CASCADE should handle this, but just in case)
    DELETE FROM message_reads
    WHERE NOT EXISTS (
        SELECT 1 FROM chat_messages
        WHERE id = message_reads.message_id
    );
    
    DELETE FROM message_reactions
    WHERE NOT EXISTS (
        SELECT 1 FROM chat_messages
        WHERE id = message_reactions.message_id
    );
    
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 7. GRANT PERMISSIONS
-- =============================================

GRANT EXECUTE ON FUNCTION get_user_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_messages(UUID, UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION send_message(UUID, UUID, VARCHAR, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_messages_read(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_store_daily_data(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_expired_messages() TO authenticated;

-- =============================================
-- CORE FUNCTIONS COMPLETE
-- =============================================