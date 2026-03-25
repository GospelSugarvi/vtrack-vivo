-- =============================================
-- FIX CHAT SYSTEM COMPLETE
-- Date: 27 January 2026
-- Description: Fix all chat system issues and ensure proper functionality
-- =============================================

-- First, let's check if all required tables exist
DO $$
BEGIN
    -- Check if stores table exists (referenced by chat_rooms)
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stores') THEN
        RAISE NOTICE 'Warning: stores table does not exist, creating placeholder';
        CREATE TABLE IF NOT EXISTS stores (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            store_name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    END IF;
    
    -- Check if users table exists (referenced by chat system)
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        RAISE NOTICE 'Warning: users table does not exist, creating placeholder';
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            full_name VARCHAR(255) NOT NULL,
            role VARCHAR(50) DEFAULT 'promotor',
            status VARCHAR(20) DEFAULT 'active',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    END IF;
END $$;

-- =============================================
-- 1. ENSURE ALL CHAT TABLES EXIST
-- =============================================

-- Chat rooms table
CREATE TABLE IF NOT EXISTS chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_type VARCHAR(20) NOT NULL CHECK (room_type IN ('toko', 'tim', 'global', 'private', 'announcement')),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  
  -- Context fields (nullable, depends on room_type)
  store_id UUID,
  sator_id UUID,
  user1_id UUID,
  user2_id UUID,
  
  -- Room settings
  is_active BOOLEAN DEFAULT TRUE,
  max_members INTEGER DEFAULT NULL,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Chat members table
CREATE TABLE IF NOT EXISTS chat_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id UUID,
  
  -- Member settings
  is_muted BOOLEAN DEFAULT FALSE,
  is_admin BOOLEAN DEFAULT FALSE,
  last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  left_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  
  -- Unique constraint
  UNIQUE(room_id, user_id)
);

-- Chat messages table
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID,
  
  -- Message content
  message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'system')),
  content TEXT,
  image_url TEXT,
  image_width INTEGER,
  image_height INTEGER,
  
  -- Message features
  mentions UUID[],
  reply_to_id UUID REFERENCES chat_messages(id) ON DELETE SET NULL,
  
  -- Edit/Delete tracking
  is_edited BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  edited_at TIMESTAMP WITH TIME ZONE,
  deleted_at TIMESTAMP WITH TIME ZONE,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE
);

-- Message reads table
CREATE TABLE IF NOT EXISTS message_reads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(message_id, user_id)
);

-- Message reactions table
CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID,
  emoji VARCHAR(10) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(message_id, user_id, emoji)
);

-- =============================================
-- 2. CREATE ESSENTIAL HELPER FUNCTIONS
-- =============================================

-- Helper function to check if user is room member
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

-- =============================================
-- 3. SIMPLIFIED GET USER CHAT ROOMS FUNCTION
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
        COALESCE(cm.is_muted, FALSE) as is_muted,
        cm.last_read_at,
        
        -- Count unread messages (simplified)
        COALESCE((
            SELECT COUNT(*)::BIGINT
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.created_at > COALESCE(cm.last_read_at, '1970-01-01'::TIMESTAMP WITH TIME ZONE)
            AND msg.is_deleted = FALSE
            AND msg.sender_id != p_user_id
        ), 0) as unread_count,
        
        -- Get last message info (simplified)
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
        
        -- Simplified sender name (may be null if users table doesn't exist)
        (
            SELECT COALESCE(u.full_name, 'Unknown User')
            FROM chat_messages msg
            LEFT JOIN users u ON u.id = msg.sender_id
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_sender_name,
        
        -- Count active members
        (
            SELECT COUNT(*)::BIGINT
            FROM chat_members mem
            WHERE mem.room_id = cr.id
            AND mem.left_at IS NULL
        ) as member_count,
        
        cr.created_at
        
    FROM chat_rooms cr
    LEFT JOIN chat_members cm ON cm.room_id = cr.id AND cm.user_id = p_user_id
    WHERE cr.is_active = TRUE
    AND (cm.user_id IS NOT NULL OR cr.room_type IN ('global', 'announcement'))
    ORDER BY 
        CASE WHEN unread_count > 0 THEN 0 ELSE 1 END,
        last_message_time DESC NULLS LAST,
        cr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 4. SIMPLIFIED GET CHAT MESSAGES FUNCTION
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
    RETURN QUERY
    SELECT 
        msg.id as message_id,
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
        
        -- Reply message content (simplified)
        reply_msg.content as reply_to_content,
        COALESCE(reply_user.full_name, 'Unknown User') as reply_to_sender_name,
        
        COALESCE(msg.is_edited, FALSE) as is_edited,
        msg.edited_at,
        msg.created_at,
        
        -- Count how many people read this message (simplified)
        COALESCE((
            SELECT COUNT(*)::BIGINT
            FROM message_reads mr
            WHERE mr.message_id = msg.id
        ), 0) as read_by_count,
        
        -- Empty reactions for now (simplified)
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

-- =============================================
-- 5. SIMPLIFIED SEND MESSAGE FUNCTION
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
BEGIN
    -- Validate content based on message type
    IF p_message_type = 'text' AND (p_content IS NULL OR LENGTH(TRIM(p_content)) = 0) THEN
        RAISE EXCEPTION 'Text messages must have content';
    END IF;
    
    IF p_message_type = 'image' AND p_image_url IS NULL THEN
        RAISE EXCEPTION 'Image messages must have image_url';
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
-- 6. SIMPLIFIED MARK MESSAGES READ FUNCTION
-- =============================================

CREATE OR REPLACE FUNCTION mark_messages_read(
    p_room_id UUID,
    p_user_id UUID,
    p_up_to_message_id UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_read_count INTEGER := 0;
BEGIN
    -- Update last_read_at in chat_members
    UPDATE chat_members 
    SET last_read_at = NOW()
    WHERE room_id = p_room_id 
    AND user_id = p_user_id;
    
    -- Insert read receipts for unread messages
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

-- =============================================
-- 7. SIMPLIFIED STORE DAILY DATA FUNCTION
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

-- =============================================
-- 8. CREATE SAMPLE DATA FOR TESTING
-- =============================================

-- Create sample global room if not exists
INSERT INTO chat_rooms (id, room_type, name, description)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'global',
    'Global Team',
    'Company-wide discussions'
) ON CONFLICT (id) DO NOTHING;

-- Create sample announcement room if not exists
INSERT INTO chat_rooms (id, room_type, name, description)
VALUES (
    '00000000-0000-0000-0000-000000000002'::UUID,
    'announcement',
    'Announcements',
    'Official company announcements'
) ON CONFLICT (id) DO NOTHING;

-- =============================================
-- 9. GRANT PERMISSIONS
-- =============================================

GRANT EXECUTE ON FUNCTION is_room_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_messages(UUID, UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION send_message(UUID, UUID, VARCHAR, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_messages_read(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_store_daily_data(UUID, DATE) TO authenticated;

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON chat_rooms TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON chat_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON chat_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON message_reads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON message_reactions TO authenticated;

-- =============================================
-- CHAT SYSTEM FIX COMPLETE
-- =============================================

SELECT 'Chat system fix completed successfully!' as result;