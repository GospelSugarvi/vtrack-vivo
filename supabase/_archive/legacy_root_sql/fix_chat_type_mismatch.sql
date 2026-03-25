-- =====================================================
-- FIX CHAT TYPE MISMATCH ERROR
-- Error: 42804 - structure of query does not match function result type
-- Date: 30 January 2026
-- =====================================================

-- First, drop all existing chat functions to avoid conflicts
DROP FUNCTION IF EXISTS get_user_chat_rooms(UUID);
DROP FUNCTION IF EXISTS get_chat_messages(UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS send_chat_message(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS mark_messages_as_read(UUID);
DROP FUNCTION IF EXISTS get_or_create_private_room(UUID);

-- =====================================================
-- 1. GET USER CHAT ROOMS (Fixed types to match table schema)
-- =====================================================
CREATE OR REPLACE FUNCTION get_user_chat_rooms(p_user_id UUID)
RETURNS TABLE (
  id UUID,
  room_type VARCHAR(20),  -- Changed from TEXT to VARCHAR(20)
  name VARCHAR(255),       -- Changed from TEXT to VARCHAR(255)
  description TEXT,
  last_message TEXT,
  last_message_at TIMESTAMPTZ,
  last_message_sender TEXT,
  unread_count BIGINT,
  member_count BIGINT,
  is_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cr.id,
    cr.room_type,
    cr.name,
    cr.description,
    cm.content as last_message,
    cm.created_at as last_message_at,
    u.full_name as last_message_sender,
    COALESCE(
      (SELECT COUNT(*) FROM chat_messages msg 
       WHERE msg.room_id = cr.id 
       AND msg.created_at > COALESCE(
         (SELECT cmem.last_read_at FROM chat_members cmem WHERE cmem.room_id = cr.id AND cmem.user_id = p_user_id),
         '1970-01-01'::timestamptz
       )
       AND msg.sender_id != p_user_id
      ), 0
    ) as unread_count,
    (SELECT COUNT(*) FROM chat_members WHERE room_id = cr.id AND left_at IS NULL) as member_count,
    cr.is_active
  FROM chat_rooms cr
  INNER JOIN chat_members crm ON cr.id = crm.room_id AND crm.left_at IS NULL
  LEFT JOIN LATERAL (
    SELECT content, created_at, sender_id 
    FROM chat_messages 
    WHERE room_id = cr.id AND is_deleted = FALSE
    ORDER BY created_at DESC 
    LIMIT 1
  ) cm ON true
  LEFT JOIN users u ON cm.sender_id = u.id
  WHERE crm.user_id = p_user_id
  AND cr.is_active = true
  ORDER BY COALESCE(cm.created_at, cr.created_at) DESC;
END;
$$;

-- =====================================================
-- 2. GET CHAT MESSAGES (Fixed types to match table schema)
-- =====================================================
CREATE OR REPLACE FUNCTION get_chat_messages(
  p_room_id UUID,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  room_id UUID,
  sender_id UUID,
  sender_name TEXT,
  sender_avatar TEXT,
  content TEXT,
  message_type VARCHAR(20),  -- Changed from TEXT to VARCHAR(20)
  attachment_url TEXT,       -- Using image_url as attachment_url
  is_read BOOLEAN,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cm.id,
    cm.room_id,
    cm.sender_id,
    u.full_name as sender_name,
    NULL::TEXT as sender_avatar,  -- Users table has no avatar_url column
    cm.content,
    cm.message_type,
    cm.image_url as attachment_url,  -- Map image_url to attachment_url
    EXISTS(SELECT 1 FROM message_reads mr WHERE mr.message_id = cm.id AND mr.user_id = auth.uid()) as is_read,
    cm.created_at
  FROM chat_messages cm
  LEFT JOIN users u ON cm.sender_id = u.id
  WHERE cm.room_id = p_room_id
  AND cm.is_deleted = FALSE
  ORDER BY cm.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- =====================================================
-- 3. SEND CHAT MESSAGE (Uses chat_members instead of chat_room_members)
-- =====================================================
CREATE OR REPLACE FUNCTION send_chat_message(
  p_room_id UUID,
  p_content TEXT,
  p_message_type TEXT DEFAULT 'text',
  p_attachment_url TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_message_id UUID;
  v_sender_id UUID;
BEGIN
  v_sender_id := auth.uid();
  
  -- Check if user is member of this room
  IF NOT EXISTS (SELECT 1 FROM chat_members WHERE room_id = p_room_id AND user_id = v_sender_id AND left_at IS NULL) THEN
    RAISE EXCEPTION 'User is not a member of this room';
  END IF;
  
  -- Insert message (map attachment_url to image_url)
  INSERT INTO chat_messages (room_id, sender_id, content, message_type, image_url)
  VALUES (p_room_id, v_sender_id, p_content, p_message_type, p_attachment_url)
  RETURNING id INTO v_message_id;
  
  -- Update room's updated_at
  UPDATE chat_rooms SET updated_at = NOW() WHERE id = p_room_id;
  
  -- Update sender's last_read_at
  UPDATE chat_members 
  SET last_read_at = NOW() 
  WHERE room_id = p_room_id AND user_id = v_sender_id;
  
  RETURN v_message_id;
END;
$$;

-- =====================================================
-- 4. MARK MESSAGES AS READ (Uses chat_members instead of chat_room_members)
-- =====================================================
CREATE OR REPLACE FUNCTION mark_messages_as_read(p_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  -- Update last_read_at in chat_members
  UPDATE chat_members 
  SET last_read_at = NOW() 
  WHERE room_id = p_room_id AND user_id = v_user_id;
  
  -- Insert read receipts for unread messages
  INSERT INTO message_reads (message_id, user_id)
  SELECT cm.id, v_user_id
  FROM chat_messages cm
  WHERE cm.room_id = p_room_id 
  AND cm.sender_id != v_user_id
  AND cm.is_deleted = FALSE
  AND NOT EXISTS (
    SELECT 1 FROM message_reads mr 
    WHERE mr.message_id = cm.id AND mr.user_id = v_user_id
  )
  ON CONFLICT (message_id, user_id) DO NOTHING;
END;
$$;

-- =====================================================
-- 5. GET OR CREATE PRIVATE ROOM (Uses chat_members instead of chat_room_members)
-- =====================================================
CREATE OR REPLACE FUNCTION get_or_create_private_room(p_other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id UUID;
  v_user_id UUID;
  v_other_name TEXT;
BEGIN
  v_user_id := auth.uid();
  
  -- Check if private room already exists
  SELECT cr.id INTO v_room_id
  FROM chat_rooms cr
  WHERE cr.room_type = 'private'
  AND (
    (cr.user1_id = v_user_id AND cr.user2_id = p_other_user_id) OR
    (cr.user1_id = p_other_user_id AND cr.user2_id = v_user_id)
  )
  LIMIT 1;
  
  -- If not, create new room
  IF v_room_id IS NULL THEN
    SELECT full_name INTO v_other_name FROM users WHERE id = p_other_user_id;
    
    INSERT INTO chat_rooms (room_type, name, user1_id, user2_id)
    VALUES ('private', v_other_name, v_user_id, p_other_user_id)
    RETURNING id INTO v_room_id;
    
    -- Add both users as members (using chat_members table)
    INSERT INTO chat_members (room_id, user_id) VALUES (v_room_id, v_user_id);
    INSERT INTO chat_members (room_id, user_id) VALUES (v_room_id, p_other_user_id);
  END IF;
  
  RETURN v_room_id;
END;
$$;

-- =====================================================
-- GRANT PERMISSIONS
-- =====================================================
GRANT EXECUTE ON FUNCTION get_user_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_chat_messages(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION send_chat_message(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_messages_as_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_or_create_private_room(UUID) TO authenticated;

-- =====================================================
-- VERIFICATION (Run after applying fix)
-- =====================================================
/*
SELECT 
  routine_name,
  data_type,
  parameter_name
FROM information_schema.routines 
WHERE routine_name LIKE '%chat%'
AND routine_schema = 'public';
*/
