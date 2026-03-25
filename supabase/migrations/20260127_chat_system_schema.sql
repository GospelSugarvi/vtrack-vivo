-- =============================================
-- CHAT SYSTEM DATABASE SCHEMA
-- Date: 27 January 2026
-- Description: Complete chat system tables and indexes
-- =============================================

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- 1. CHAT ROOMS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_type VARCHAR(20) NOT NULL CHECK (room_type IN ('toko', 'tim', 'global', 'private', 'announcement')),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  
  -- Context fields (nullable, depends on room_type)
  store_id UUID REFERENCES stores(id) ON DELETE CASCADE,
  sator_id UUID REFERENCES users(id) ON DELETE CASCADE,
  user1_id UUID REFERENCES users(id) ON DELETE CASCADE, -- for private chats
  user2_id UUID REFERENCES users(id) ON DELETE CASCADE, -- for private chats
  
  -- Room settings
  is_active BOOLEAN DEFAULT TRUE,
  max_members INTEGER DEFAULT NULL, -- NULL = unlimited
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT valid_private_chat CHECK (
    (room_type = 'private' AND user1_id IS NOT NULL AND user2_id IS NOT NULL AND user1_id != user2_id)
    OR room_type != 'private'
  ),
  CONSTRAINT valid_store_chat CHECK (
    (room_type = 'toko' AND store_id IS NOT NULL)
    OR room_type != 'toko'
  ),
  CONSTRAINT valid_tim_chat CHECK (
    (room_type = 'tim' AND sator_id IS NOT NULL)
    OR room_type != 'tim'
  )
);

-- =============================================
-- 2. CHAT MEMBERS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS chat_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  
  -- Member settings
  is_muted BOOLEAN DEFAULT FALSE,
  is_admin BOOLEAN DEFAULT FALSE, -- for future use
  last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  left_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  
  -- Unique constraint
  UNIQUE(room_id, user_id)
);

-- =============================================
-- 3. CHAT MESSAGES TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
  
  -- Message content
  message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'system')),
  content TEXT,
  image_url TEXT,
  image_width INTEGER,
  image_height INTEGER,
  
  -- Message features
  mentions UUID[], -- array of mentioned user_ids
  reply_to_id UUID REFERENCES chat_messages(id) ON DELETE SET NULL,
  
  -- Edit/Delete tracking
  is_edited BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  edited_at TIMESTAMP WITH TIME ZONE,
  deleted_at TIMESTAMP WITH TIME ZONE,
  
  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE, -- for auto-cleanup
  
  -- Constraints
  CONSTRAINT valid_content CHECK (
    (message_type = 'text' AND content IS NOT NULL AND LENGTH(TRIM(content)) > 0)
    OR (message_type = 'image' AND image_url IS NOT NULL)
    OR message_type = 'system'
  ),
  CONSTRAINT valid_edit_time CHECK (
    edited_at IS NULL OR edited_at >= created_at
  )
);

-- =============================================
-- 4. MESSAGE READS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS message_reads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Unique constraint
  UNIQUE(message_id, user_id)
);

-- =============================================
-- 5. MESSAGE REACTIONS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  emoji VARCHAR(10) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Unique constraint (one reaction per user per message per emoji)
  UNIQUE(message_id, user_id, emoji)
);
-- =============================================
-- 6. PERFORMANCE INDEXES
-- =============================================

-- Chat rooms indexes
CREATE INDEX IF NOT EXISTS idx_chat_rooms_type ON chat_rooms(room_type);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_store ON chat_rooms(store_id) WHERE store_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_sator ON chat_rooms(sator_id) WHERE sator_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_private ON chat_rooms(user1_id, user2_id) WHERE room_type = 'private';
CREATE INDEX IF NOT EXISTS idx_chat_rooms_active ON chat_rooms(is_active, created_at DESC);

-- Chat members indexes
CREATE INDEX IF NOT EXISTS idx_chat_members_room ON chat_members(room_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_user ON chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_active ON chat_members(room_id, user_id) WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_chat_members_last_read ON chat_members(room_id, last_read_at);

-- Chat messages indexes (most critical for performance)
CREATE INDEX IF NOT EXISTS idx_chat_messages_room_time ON chat_messages(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender ON chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_reply ON chat_messages(reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_mentions ON chat_messages USING GIN(mentions) WHERE mentions IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_expires ON chat_messages(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_active ON chat_messages(room_id, created_at DESC) WHERE is_deleted = FALSE;

-- Message reads indexes
CREATE INDEX IF NOT EXISTS idx_message_reads_message ON message_reads(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reads_user ON message_reads(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reads_time ON message_reads(read_at DESC);

-- Message reactions indexes
CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user ON message_reactions(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_emoji ON message_reactions(message_id, emoji);

-- =============================================
-- 7. UPDATED_AT TRIGGER FUNCTION
-- =============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to chat_rooms
CREATE TRIGGER trigger_chat_rooms_updated_at
    BEFORE UPDATE ON chat_rooms
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- 8. AUTO-EXPIRE MESSAGES FUNCTION
-- =============================================
CREATE OR REPLACE FUNCTION set_message_expiry()
RETURNS TRIGGER AS $$
BEGIN
    -- Set expiry based on room type
    IF NEW.expires_at IS NULL THEN
        SELECT room_type INTO NEW.expires_at
        FROM chat_rooms 
        WHERE id = NEW.room_id;
        
        -- Set expiry time based on room type
        CASE 
            WHEN (SELECT room_type FROM chat_rooms WHERE id = NEW.room_id) = 'announcement' THEN
                NEW.expires_at := NEW.created_at + INTERVAL '6 months';
            ELSE
                NEW.expires_at := NEW.created_at + INTERVAL '1 month';
        END CASE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to chat_messages
CREATE TRIGGER trigger_set_message_expiry
    BEFORE INSERT ON chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION set_message_expiry();

-- =============================================
-- 9. INITIAL DATA - GLOBAL AND ANNOUNCEMENT ROOMS
-- =============================================

-- Create Global chat room
INSERT INTO chat_rooms (id, room_type, name, description)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'global',
    'Global Team',
    'Company-wide discussions and cross-team communication'
) ON CONFLICT (id) DO NOTHING;

-- Create Announcement room
INSERT INTO chat_rooms (id, room_type, name, description)
VALUES (
    '00000000-0000-0000-0000-000000000002'::UUID,
    'announcement',
    'Announcements',
    'Official company announcements from SPV and Admin'
) ON CONFLICT (id) DO NOTHING;

-- =============================================
-- 10. COMMENTS
-- =============================================

COMMENT ON TABLE chat_rooms IS 'Chat rooms for different types of conversations';
COMMENT ON TABLE chat_members IS 'Membership tracking for chat rooms';
COMMENT ON TABLE chat_messages IS 'All chat messages with content and metadata';
COMMENT ON TABLE message_reads IS 'Read receipts for messages';
COMMENT ON TABLE message_reactions IS 'Emoji reactions to messages';

COMMENT ON COLUMN chat_rooms.room_type IS 'Type: toko, tim, global, private, announcement';
COMMENT ON COLUMN chat_messages.mentions IS 'Array of user UUIDs mentioned in message';
COMMENT ON COLUMN chat_messages.expires_at IS 'Auto-deletion time (1 month for regular, 6 months for announcements)';

-- =============================================
-- SCHEMA CREATION COMPLETE
-- =============================================