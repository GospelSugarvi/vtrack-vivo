-- =============================================
-- CHAT SYSTEM AUTOMATIC ROOM MANAGEMENT
-- Date: 27 January 2026
-- Description: Automatic creation and management of chat rooms
-- =============================================

SET search_path = public;

-- =============================================
-- 1. AUTO-CREATE STORE CHAT ROOM
-- =============================================

CREATE OR REPLACE FUNCTION create_store_chat_room()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id UUID;
BEGIN
    -- Create chat room for the new store
    INSERT INTO chat_rooms (room_type, name, description, toko_id)
    VALUES (
        'toko',
        NEW.name,
        'Chat r