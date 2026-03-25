-- =====================================================
-- CHECK CHAT SYSTEM - Verification Script
-- =====================================================

-- 1. Check chat tables exist
SELECT 
  table_name,
  CASE WHEN table_name IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
  'chat_rooms',
  'chat_messages',
  'chat_room_members'
)
ORDER BY table_name;

-- 2. Check chat_rooms columns
SELECT column_name, data_type
FROM information_schema.columns 
WHERE table_name = 'chat_rooms'
ORDER BY ordinal_position;

-- 3. Check if global and announcement rooms exist
SELECT id, room_type, name, is_active
FROM chat_rooms
WHERE room_type IN ('global', 'announcement');

-- 4. Check functions exist
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE '%chat%'
ORDER BY routine_name;

-- 5. Count chat room members
SELECT 
  (SELECT COUNT(*) FROM chat_room_members) as total_members,
  (SELECT COUNT(DISTINCT room_id) FROM chat_room_members) as rooms_with_members,
  (SELECT COUNT(DISTINCT user_id) FROM chat_room_members) as unique_users;
