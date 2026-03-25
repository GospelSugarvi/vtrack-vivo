-- =============================================
-- CHAT SYSTEM ROW LEVEL SECURITY (RLS)
-- Date: 27 January 2026
-- Description: Security policies for chat system
-- =============================================

-- =============================================
-- 1. ENABLE RLS ON ALL CHAT TABLES
-- =============================================

ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;

-- =============================================
-- 2. HELPER FUNCTION - CHECK ROOM MEMBERSHIP
-- =============================================

CREATE OR REPLACE FUNCTION is_room_member(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM chat_members 
        WHERE room_id = room_uuid 
        AND user_id = user_uuid 
        AND left_at IS NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 3. CHAT_ROOMS POLICIES
-- =============================================

-- Users can view rooms they are members of
CREATE POLICY "Users can view their chat rooms" ON chat_rooms
    FOR SELECT USING (
        is_room_member(id, auth.uid())
    );

-- Only admins can create/update/delete rooms (handled by functions)
CREATE POLICY "Only system can modify rooms" ON chat_rooms
    FOR ALL USING (false);

-- =============================================
-- 4. CHAT_MEMBERS POLICIES
-- =============================================

-- Users can view memberships for rooms they belong to
CREATE POLICY "Users can view room memberships" ON chat_members
    FOR SELECT USING (
        is_room_member(room_id, auth.uid())
    );

-- Users can update their own membership settings (mute, last_read_at)
CREATE POLICY "Users can update own membership" ON chat_members
    FOR UPDATE USING (
        user_id = auth.uid()
    ) WITH CHECK (
        user_id = auth.uid() AND
        -- Can only update specific fields
        OLD.room_id = NEW.room_id AND
        OLD.user_id = NEW.user_id AND
        OLD.joined_at = NEW.joined_at
    );

-- Only system can insert/delete memberships
CREATE POLICY "Only system can manage memberships" ON chat_members
    FOR INSERT WITH CHECK (false);

CREATE POLICY "Only system can remove memberships" ON chat_members
    FOR DELETE USING (false);

-- =============================================
-- 5. CHAT_MESSAGES POLICIES
-- =============================================

-- Users can view messages in rooms they belong to
CREATE POLICY "Users can view room messages" ON chat_messages
    FOR SELECT USING (
        is_room_member(room_id, auth.uid()) AND
        is_deleted = FALSE
    );

-- Users can send messages to rooms they belong to
CREATE POLICY "Users can send messages" ON chat_messages
    FOR INSERT WITH CHECK (
        sender_id = auth.uid() AND
        is_room_member(room_id, auth.uid())
    );

-- Users can edit their own messages (within time limit - enforced by function)
CREATE POLICY "Users can edit own messages" ON chat_messages
    FOR UPDATE USING (
        sender_id = auth.uid() AND
        is_room_member(room_id, auth.uid())
    ) WITH CHECK (
        sender_id = auth.uid() AND
        -- Prevent changing critical fields
        OLD.room_id = NEW.room_id AND
        OLD.sender_id = NEW.sender_id AND
        OLD.created_at = NEW.created_at
    );

-- Users can delete their own messages (within time limit - enforced by function)
CREATE POLICY "Users can delete own messages" ON chat_messages
    FOR DELETE USING (
        sender_id = auth.uid() AND
        is_room_member(room_id, auth.uid())
    );

-- =============================================
-- 6. MESSAGE_READS POLICIES
-- =============================================

-- Users can view read receipts for messages in their rooms
CREATE POLICY "Users can view read receipts" ON message_reads
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM chat_messages cm
            WHERE cm.id = message_id
            AND is_room_member(cm.room_id, auth.uid())
        )
    );

-- Users can mark messages as read
CREATE POLICY "Users can mark messages read" ON message_reads
    FOR INSERT WITH CHECK (
        user_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM chat_messages cm
            WHERE cm.id = message_id
            AND is_room_member(cm.room_id, auth.uid())
        )
    );

-- Users can update their own read receipts
CREATE POLICY "Users can update own read receipts" ON message_reads
    FOR UPDATE USING (
        user_id = auth.uid()
    ) WITH CHECK (
        user_id = auth.uid() AND
        OLD.message_id = NEW.message_id AND
        OLD.user_id = NEW.user_id
    );

-- Users can delete their own read receipts (if needed)
CREATE POLICY "Users can delete own read receipts" ON message_reads
    FOR DELETE USING (
        user_id = auth.uid()
    );

-- =============================================
-- 7. MESSAGE_REACTIONS POLICIES
-- =============================================

-- Users can view reactions for messages in their rooms
CREATE POLICY "Users can view message reactions" ON message_reactions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM chat_messages cm
            WHERE cm.id = message_id
            AND is_room_member(cm.room_id, auth.uid())
        )
    );

-- Users can add reactions to messages in their rooms
CREATE POLICY "Users can add reactions" ON message_reactions
    FOR INSERT WITH CHECK (
        user_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM chat_messages cm
            WHERE cm.id = message_id
            AND is_room_member(cm.room_id, auth.uid())
        )
    );

-- Users can remove their own reactions
CREATE POLICY "Users can remove own reactions" ON message_reactions
    FOR DELETE USING (
        user_id = auth.uid()
    );

-- =============================================
-- 8. SPECIAL POLICIES FOR ANNOUNCEMENT ROOMS
-- =============================================

-- Override message insert policy for announcement rooms (only SPV/Admin can post)
CREATE POLICY "Only SPV/Admin can post announcements" ON chat_messages
    FOR INSERT WITH CHECK (
        CASE 
            WHEN (SELECT room_type FROM chat_rooms WHERE id = room_id) = 'announcement' THEN
                EXISTS (
                    SELECT 1 FROM users 
                    WHERE id = auth.uid() 
                    AND role IN ('spv', 'admin')
                )
            ELSE true
        END
    );

-- =============================================
-- 9. GRANT PERMISSIONS
-- =============================================

-- Grant usage on functions
GRANT EXECUTE ON FUNCTION is_room_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_updated_at_column() TO authenticated;
GRANT EXECUTE ON FUNCTION set_message_expiry() TO authenticated;

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON chat_rooms TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON chat_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON chat_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON message_reads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON message_reactions TO authenticated;

-- =============================================
-- RLS SETUP COMPLETE
-- =============================================