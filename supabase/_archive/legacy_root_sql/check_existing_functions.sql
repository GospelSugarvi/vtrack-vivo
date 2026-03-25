-- Check existing function signatures
SELECT 
    routine_name,
    routine_type,
    data_type,
    routine_definition
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('get_user_chat_rooms', 'get_chat_messages', 'send_message', 'mark_messages_read', 'get_store_daily_data', 'is_room_member')
ORDER BY routine_name;

-- Check function parameters
SELECT 
    routine_name,
    parameter_name,
    data_type,
    parameter_mode
FROM information_schema.parameters
WHERE specific_schema = 'public'
AND routine_name IN ('get_user_chat_rooms', 'get_chat_messages', 'send_message', 'mark_messages_read', 'get_store_daily_data', 'is_room_member')
ORDER BY routine_name, ordinal_position;