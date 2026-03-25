-- =====================================================
-- FIX CHAT SYSTEM V6 (IMAGE UPLOAD FIX)
-- Date: 30 January 2026
-- Description: Relaxes parameter types for send_message to ensure image uploads
--              via Cloudinary (URL reference) work correctly.
-- =====================================================

-- 1. DROP EXISTING FUNCTION
DROP FUNCTION IF EXISTS send_message(UUID, UUID, VARCHAR, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID);
DROP FUNCTION IF EXISTS send_message(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, UUID[], UUID);
DROP FUNCTION IF EXISTS send_message(UUID, UUID, VARCHAR, TEXT, TEXT, UUID[], UUID, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS send_message(UUID, UUID, TEXT, TEXT, TEXT, UUID[], UUID, INTEGER, INTEGER);

-- =====================================================
-- 2. SEND MESSAGE (Flexible Types)
-- =====================================================
CREATE OR REPLACE FUNCTION send_message(
    p_room_id UUID,
    p_sender_id UUID,
    p_message_type TEXT DEFAULT 'text', -- Changed to TEXT for safety
    p_content TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL,
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
    v_final_type VARCHAR(20);
BEGIN
    -- Cast type safely
    v_final_type := p_message_type::VARCHAR(20);

    -- Validation
    IF v_final_type = 'text' AND (p_content IS NULL OR LENGTH(TRIM(p_content)) = 0) THEN
        RAISE EXCEPTION 'Text messages must have content';
    END IF;
    
    IF v_final_type = 'image' AND p_image_url IS NULL THEN
        RAISE EXCEPTION 'Image messages must have image_url';
    END IF;

    -- Insert
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
        v_final_type, -- Use casted variable
        p_content, 
        p_image_url,
        p_image_width, 
        p_image_height, 
        p_mentions, 
        p_reply_to_id
    ) RETURNING id INTO v_message_id;
    
    -- Update Room & Member Stats
    UPDATE chat_rooms SET updated_at = NOW() WHERE id = p_room_id;
    UPDATE chat_members SET last_read_at = NOW() WHERE room_id = p_room_id AND user_id = p_sender_id;
    
    RETURN v_message_id;
END;
$$;

-- Alias for compatibility (if needed)
CREATE OR REPLACE FUNCTION send_chat_message(
    p_room_id UUID,
    p_content TEXT,
    p_message_type TEXT DEFAULT 'text',
    p_attachment_url TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN send_message(
        p_room_id := p_room_id,
        p_sender_id := auth.uid(),
        p_message_type := p_message_type,
        p_content := p_content,
        p_image_url := p_attachment_url
    );
END;
$$;

-- =====================================================
-- PERMISSIONS
-- =====================================================
GRANT EXECUTE ON FUNCTION send_message(UUID, UUID, TEXT, TEXT, TEXT, UUID[], UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION send_chat_message(UUID, TEXT, TEXT, TEXT) TO authenticated;
