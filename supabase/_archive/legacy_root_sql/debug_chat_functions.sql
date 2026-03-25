-- Debug Chat Functions
-- Check if chat functions exist and work properly

-- 1. Check if functions exist
SELECT 
    routine_name,
    routine_type,
    data_type
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name LIKE '%chat%'
ORDER BY routine_name;

-- 2. Check if tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE '%chat%'
ORDER BY table_name;

-- 3. Test get_user_chat_rooms function
-- Replace 'your-user-id' with actual user ID
DO $$
DECLARE
    test_user_id UUID := (SELECT id FROM auth.users LIMIT 1);
BEGIN
    IF test_user_id IS NOT NULL THEN
        RAISE NOTICE 'Testing get_user_chat_rooms with user: %', test_user_id;
        
        -- Test the function
        PERFORM get_user_chat_rooms(test_user_id);
        RAISE NOTICE 'get_user_chat_rooms function works';
    ELSE
        RAISE NOTICE 'No users found in auth.users table';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error testing get_user_chat_rooms: %', SQLERRM;
END $$;

-- 4. Test get_chat_messages function
DO $$
DECLARE
    test_user_id UUID := (SELECT id FROM auth.users LIMIT 1);
    test_room_id UUID := (SELECT id FROM chat_rooms LIMIT 1);
BEGIN
    IF test_user_id IS NOT NULL AND test_room_id IS NOT NULL THEN
        RAISE NOTICE 'Testing get_chat_messages with user: % and room: %', test_user_id, test_room_id;
        
        -- Test the function
        PERFORM get_chat_messages(test_room_id, test_user_id, 10, 0);
        RAISE NOTICE 'get_chat_messages function works';
    ELSE
        RAISE NOTICE 'No users or rooms found for testing';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error testing get_chat_messages: %', SQLERRM;
END $$;

-- 5. Check chat_rooms table structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'chat_rooms' 
AND table_schema = 'public'
ORDER BY ordinal_position;

-- 6. Check chat_messages table structure  
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'chat_messages' 
AND table_schema = 'public'
ORDER BY ordinal_position;

-- 7. Check if there are any chat rooms
SELECT 
    id,
    room_type,
    room_name,
    created_at
FROM chat_rooms 
LIMIT 5;

-- 8. Check if there are any chat messages
SELECT 
    id,
    room_id,
    sender_id,
    message_type,
    content,
    created_at
FROM chat_messages 
LIMIT 5;