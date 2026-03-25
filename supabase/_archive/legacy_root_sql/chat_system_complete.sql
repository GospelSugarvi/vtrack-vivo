-- =============================================
-- COMPLETE CHAT SYSTEM IMPLEMENTATION
-- =============================================
-- This file combines all chat system migrations with corrected schema references
-- Execute this file to set up the complete chat system

-- =============================================
-- 1. CHAT SYSTEM SCHEMA
-- =============================================

-- Chat Rooms Table
CREATE TABLE IF NOT EXISTS chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_type VARCHAR(20) NOT NULL CHECK (room_type IN ('toko', 'tim', 'global', 'private', 'announcement')),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  store_id UUID REFERENCES stores(id),
  team_lead_id UUID REFERENCES users(id),
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Business Logic Constraints
  CONSTRAINT valid_store_chat CHECK (
    (room_type = 'toko' AND store_id IS NOT NULL)
    OR room_type != 'toko'
  ),
  CONSTRAINT valid_tim_chat CHECK (
    (room_type = 'tim' AND team_lead_id IS NOT NULL)
    OR room_type != 'tim'
  )
);

-- Chat Members Table
CREATE TABLE IF NOT EXISTS chat_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('admin', 'moderator', 'member')),
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  last_read_at TIMESTAMPTZ DEFAULT NOW(),
  is_muted BOOLEAN DEFAULT FALSE,
  
  UNIQUE(room_id, user_id)
);

-- Chat Messages Table
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id),
  message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'file', 'system', 'store_data')),
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  mentions UUID[] DEFAULT '{}',
  reply_to_id UUID REFERENCES chat_messages(id),
  expires_at TIMESTAMPTZ,
  is_edited BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Message Reads Table
CREATE TABLE IF NOT EXISTS message_reads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(message_id, user_id)
);

-- Message Reactions Table
CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(message_id, user_id, emoji)
);

-- =============================================
-- 2. INDEXES FOR PERFORMANCE
-- =============================================

-- Unique constraints using partial indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_store_room ON chat_rooms(store_id, room_type) WHERE room_type = 'toko';
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_team_room ON chat_rooms(team_lead_id, room_type) WHERE room_type = 'tim';
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_global_room ON chat_rooms(room_type) WHERE room_type = 'global';

-- Regular indexes
CREATE INDEX IF NOT EXISTS idx_chat_rooms_type ON chat_rooms(room_type);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_store ON chat_rooms(store_id) WHERE store_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_team_lead ON chat_rooms(team_lead_id) WHERE team_lead_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_active ON chat_rooms(is_active) WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_chat_members_room ON chat_members(room_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user ON chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_room_user ON chat_members(room_id, user_id);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room ON chat_messages(room_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created ON chat_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_room_created ON chat_messages(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_type ON chat_messages(message_type);
CREATE INDEX IF NOT EXISTS idx_chat_messages_mentions ON chat_messages USING GIN(mentions);
CREATE INDEX IF NOT EXISTS idx_chat_messages_reply ON chat_messages(reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_expires ON chat_messages(expires_at) WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_message_reads_message ON message_reads(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reads_user ON message_reads(user_id);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user ON message_reactions(user_id);

-- =============================================
-- 3. TRIGGERS
-- =============================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_chat_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER chat_rooms_updated_at
  BEFORE UPDATE ON chat_rooms
  FOR EACH ROW EXECUTE FUNCTION update_chat_updated_at();

CREATE TRIGGER chat_messages_updated_at
  BEFORE UPDATE ON chat_messages
  FOR EACH ROW EXECUTE FUNCTION update_chat_updated_at();

-- Auto-expire messages trigger
CREATE OR REPLACE FUNCTION set_message_expiry()
RETURNS TRIGGER AS $$
BEGIN
  -- Set expiry for regular messages (1 month)
  IF NEW.message_type IN ('text', 'image', 'file') THEN
    NEW.expires_at = NOW() + INTERVAL '1 month';
  -- Set expiry for announcements (6 months)
  ELSIF NEW.message_type = 'system' THEN
    NEW.expires_at = NOW() + INTERVAL '6 months';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER chat_messages_set_expiry
  BEFORE INSERT ON chat_messages
  FOR EACH ROW EXECUTE FUNCTION set_message_expiry();

-- =============================================
-- 4. CHAT SYSTEM FUNCTIONS
-- =============================================

-- Get user's chat rooms
CREATE OR REPLACE FUNCTION get_user_chat_rooms(p_user_id UUID)
RETURNS TABLE (
    room_id UUID,
    room_type VARCHAR(20),
    room_name VARCHAR(255),
    description TEXT,
    store_id UUID,
    team_lead_id UUID,
    is_active BOOLEAN,
    member_role VARCHAR(20),
    last_message_content TEXT,
    last_message_at TIMESTAMPTZ,
    unread_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cr.id as room_id,
        cr.room_type,
        cr.name as room_name,
        cr.description,
        cr.store_id,
        cr.team_lead_id,
        cr.is_active,
        cm.role as member_role,
        
        -- Last message content
        (
            SELECT content
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_content,
        
        -- Last message timestamp
        (
            SELECT created_at
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) as last_message_at,
        
        -- Unread count
        (
            SELECT COUNT(*)
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.sender_id != p_user_id
            AND msg.is_deleted = FALSE
            AND msg.created_at > COALESCE(cm.last_read_at, '1970-01-01'::timestamptz)
            AND NOT EXISTS (
                SELECT 1 FROM message_reads mr
                WHERE mr.message_id = msg.id
                AND mr.user_id = p_user_id
            )
        ) as unread_count
        
    FROM chat_rooms cr
    JOIN chat_members cm ON cm.room_id = cr.id
    WHERE cm.user_id = p_user_id
    AND cr.is_active = TRUE
    ORDER BY 
        CASE 
            WHEN cr.room_type = 'global' THEN 1
            WHEN cr.room_type = 'announcement' THEN 2
            WHEN cr.room_type = 'toko' THEN 3
            WHEN cr.room_type = 'tim' THEN 4
            WHEN cr.room_type = 'private' THEN 5
            ELSE 6
        END,
        (
            SELECT created_at
            FROM chat_messages msg
            WHERE msg.room_id = cr.id
            AND msg.is_deleted = FALSE
            ORDER BY msg.created_at DESC
            LIMIT 1
        ) DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get chat messages with pagination
CREATE OR REPLACE FUNCTION get_chat_messages(
    p_room_id UUID,
    p_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    message_id UUID,
    sender_id UUID,
    sender_name TEXT,
    message_type VARCHAR(20),
    content TEXT,
    metadata JSONB,
    mentions UUID[],
    reply_to_id UUID,
    reply_to_content TEXT,
    reply_to_sender TEXT,
    is_edited BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    is_read BOOLEAN,
    reactions JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        msg.id as message_id,
        msg.sender_id,
        u.full_name as sender_name,
        msg.message_type,
        msg.content,
        msg.metadata,
        msg.mentions,
        msg.reply_to_id,
        
        -- Reply message content
        (
            SELECT content
            FROM chat_messages reply_msg
            WHERE reply_msg.id = msg.reply_to_id
        ) as reply_to_content,
        
        -- Reply message sender
        (
            SELECT u2.full_name
            FROM chat_messages reply_msg
            JOIN users u2 ON u2.id = reply_msg.sender_id
            WHERE reply_msg.id = msg.reply_to_id
        ) as reply_to_sender,
        
        msg.is_edited,
        msg.created_at,
        msg.updated_at,
        
        -- Check if message is read by current user
        EXISTS (
            SELECT 1 FROM message_reads mr
            WHERE mr.message_id = msg.id
            AND mr.user_id = p_user_id
        ) as is_read,
        
        -- Aggregate reactions
        COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'emoji', mr.emoji,
                    'count', reaction_counts.count,
                    'users', reaction_counts.users,
                    'user_reacted', reaction_counts.user_reacted
                )
            )
            FROM (
                SELECT 
                    mr.emoji,
                    COUNT(*) as count,
                    jsonb_agg(u3.full_name) as users,
                    bool_or(mr.user_id = p_user_id) as user_reacted
                FROM message_reactions mr
                JOIN users u3 ON u3.id = mr.user_id
                WHERE mr.message_id = msg.id
                GROUP BY mr.emoji
            ) reaction_counts
        ), '[]'::jsonb) as reactions
        
    FROM chat_messages msg
    JOIN users u ON u.id = msg.sender_id
    WHERE msg.room_id = p_room_id
    AND msg.is_deleted = FALSE
    ORDER BY msg.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Send message function
CREATE OR REPLACE FUNCTION send_message(
    p_room_id UUID,
    p_sender_id UUID,
    p_message_type VARCHAR(20) DEFAULT 'text',
    p_content TEXT DEFAULT '',
    p_metadata TEXT DEFAULT '{}',
    p_expires_hours INTEGER DEFAULT NULL,
    p_expires_days INTEGER DEFAULT NULL,
    p_mentions UUID[] DEFAULT '{}',
    p_reply_to_id UUID DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_message_id UUID;
    v_expires_at TIMESTAMPTZ := NULL;
BEGIN
    -- Calculate expiry if specified
    IF p_expires_hours IS NOT NULL THEN
        v_expires_at := NOW() + (p_expires_hours || ' hours')::INTERVAL;
    ELSIF p_expires_days IS NOT NULL THEN
        v_expires_at := NOW() + (p_expires_days || ' days')::INTERVAL;
    END IF;
    
    -- Insert message
    INSERT INTO chat_messages (
        room_id,
        sender_id,
        message_type,
        content,
        metadata,
        mentions,
        reply_to_id,
        expires_at
    ) VALUES (
        p_room_id,
        p_sender_id,
        p_message_type,
        p_content,
        p_metadata::jsonb,
        p_mentions,
        p_reply_to_id,
        v_expires_at
    ) RETURNING id INTO v_message_id;
    
    -- Auto-mark as read for sender
    INSERT INTO message_reads (message_id, user_id)
    VALUES (v_message_id, p_sender_id);
    
    RETURN v_message_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Mark messages as read
CREATE OR REPLACE FUNCTION mark_messages_read(
    p_room_id UUID,
    p_user_id UUID,
    p_message_id UUID DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_read_count INTEGER := 0;
BEGIN
    IF p_message_id IS NOT NULL THEN
        -- Mark specific message as read
        INSERT INTO message_reads (message_id, user_id)
        VALUES (p_message_id, p_user_id)
        ON CONFLICT (message_id, user_id) DO NOTHING;
        
        -- Update member's last read timestamp
        UPDATE chat_members
        SET last_read_at = NOW()
        WHERE room_id = p_room_id AND user_id = p_user_id;
        
        -- Count affected rows
        SELECT COUNT(*) INTO v_read_count
        FROM message_reads mr
        JOIN chat_messages msg ON msg.id = mr.message_id
        WHERE mr.message_id = p_message_id
        AND mr.user_id = p_user_id;
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

-- Get store daily data for toko rooms
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
        
        -- Promotion posts (placeholder)
        0 as promotion_posts
        
    FROM stores s
    WHERE s.id = p_store_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Message cleanup function
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
-- 5. ROW LEVEL SECURITY (RLS)
-- =============================================

-- Enable RLS
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;

-- Chat Rooms Policies
CREATE POLICY "Users can view rooms they are members of" ON chat_rooms
    FOR SELECT USING (
        id IN (
            SELECT room_id FROM chat_members 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Admins can manage all rooms" ON chat_rooms
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Chat Members Policies
CREATE POLICY "Users can view memberships in their rooms" ON chat_members
    FOR SELECT USING (
        room_id IN (
            SELECT room_id FROM chat_members 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Room admins can manage members" ON chat_members
    FOR ALL USING (
        room_id IN (
            SELECT room_id FROM chat_members 
            WHERE user_id = auth.uid() 
            AND role IN ('admin', 'moderator')
        )
        OR EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Chat Messages Policies
CREATE POLICY "Users can view messages in their rooms" ON chat_messages
    FOR SELECT USING (
        room_id IN (
            SELECT room_id FROM chat_members 
            WHERE user_id = auth.uid()
        )
        AND is_deleted = FALSE
    );

CREATE POLICY "Users can send messages to their rooms" ON chat_messages
    FOR INSERT WITH CHECK (
        room_id IN (
            SELECT room_id FROM chat_members 
            WHERE user_id = auth.uid()
        )
        AND sender_id = auth.uid()
    );

CREATE POLICY "Users can edit their own messages" ON chat_messages
    FOR UPDATE USING (
        sender_id = auth.uid()
        AND room_id IN (
            SELECT room_id FROM chat_members 
            WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete their own messages" ON chat_messages
    FOR DELETE USING (
        sender_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Message Reads Policies
CREATE POLICY "Users can manage their own read receipts" ON message_reads
    FOR ALL USING (user_id = auth.uid());

-- Message Reactions Policies
CREATE POLICY "Users can manage reactions in their rooms" ON message_reactions
    FOR ALL USING (
        message_id IN (
            SELECT msg.id FROM chat_messages msg
            JOIN chat_members cm ON cm.room_id = msg.room_id
            WHERE cm.user_id = auth.uid()
        )
    );

-- =============================================
-- 6. AUTO ROOM MANAGEMENT
-- =============================================

-- Function to auto-create store rooms
CREATE OR REPLACE FUNCTION auto_create_store_rooms()
RETURNS VOID AS $$
BEGIN
    -- Create toko rooms for stores that don't have them
    INSERT INTO chat_rooms (room_type, name, description, store_id, created_by)
    SELECT 
        'toko',
        'Chat ' || s.store_name,
        'Chat room untuk toko ' || s.store_name,
        s.id,
        (SELECT id FROM users WHERE role = 'admin' LIMIT 1)
    FROM stores s
    WHERE s.status = 'active'
    AND NOT EXISTS (
        SELECT 1 FROM chat_rooms cr
        WHERE cr.store_id = s.id
        AND cr.room_type = 'toko'
    );
    
    -- Auto-add promotors to their store rooms
    INSERT INTO chat_members (room_id, user_id, role)
    SELECT DISTINCT
        cr.id,
        aps.promotor_id,
        'member'
    FROM chat_rooms cr
    JOIN assignments_promotor_store aps ON aps.store_id = cr.store_id
    JOIN users u ON u.id = aps.promotor_id
    WHERE cr.room_type = 'toko'
    AND aps.active = TRUE
    AND u.status = 'active'
    AND NOT EXISTS (
        SELECT 1 FROM chat_members cm
        WHERE cm.room_id = cr.id
        AND cm.user_id = aps.promotor_id
    );
    
    -- Auto-add sators to their promotors' store rooms
    INSERT INTO chat_members (room_id, user_id, role)
    SELECT DISTINCT
        cr.id,
        hsp.sator_id,
        'moderator'
    FROM chat_rooms cr
    JOIN assignments_promotor_store aps ON aps.store_id = cr.store_id
    JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = aps.promotor_id
    JOIN users u ON u.id = hsp.sator_id
    WHERE cr.room_type = 'toko'
    AND aps.active = TRUE
    AND hsp.active = TRUE
    AND u.status = 'active'
    AND NOT EXISTS (
        SELECT 1 FROM chat_members cm
        WHERE cm.room_id = cr.id
        AND cm.user_id = hsp.sator_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to create global room if not exists
CREATE OR REPLACE FUNCTION ensure_global_room()
RETURNS VOID AS $$
BEGIN
    -- Create global room if it doesn't exist
    INSERT INTO chat_rooms (room_type, name, description, created_by)
    SELECT 
        'global',
        'Chat Global',
        'Chat room untuk semua pengguna',
        (SELECT id FROM users WHERE role = 'admin' LIMIT 1)
    WHERE NOT EXISTS (
        SELECT 1 FROM chat_rooms
        WHERE room_type = 'global'
    );
    
    -- Add all active users to global room
    INSERT INTO chat_members (room_id, user_id, role)
    SELECT 
        (SELECT id FROM chat_rooms WHERE room_type = 'global' LIMIT 1),
        u.id,
        CASE 
            WHEN u.role = 'admin' THEN 'admin'
            WHEN u.role IN ('manager', 'spv') THEN 'moderator'
            ELSE 'member'
        END
    FROM users u
    WHERE u.status = 'active'
    AND NOT EXISTS (
        SELECT 1 FROM chat_members cm
        JOIN chat_rooms cr ON cr.id = cm.room_id
        WHERE cr.room_type = 'global'
        AND cm.user_id = u.id
    );
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
GRANT EXECUTE ON FUNCTION auto_create_store_rooms() TO authenticated;
GRANT EXECUTE ON FUNCTION ensure_global_room() TO authenticated;

-- =============================================
-- 8. INITIAL SETUP
-- =============================================

-- Create global room and auto-create store rooms
SELECT ensure_global_room();
SELECT auto_create_store_rooms();

-- =============================================
-- CHAT SYSTEM SETUP COMPLETE
-- =============================================