-- Debug leaderboard feed function

-- 1. Check if function exists
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'get_leaderboard_feed';

-- 2. Check sales data for today
SELECT 
  DATE(s.created_at AT TIME ZONE 'Asia/Makassar') as sale_date,
  u.full_name as promotor_name,
  u.area_id,
  a.name as area_name,
  s.bonus,
  s.created_at
FROM sales_sell_out s
JOIN users u ON u.id = s.promotor_id
LEFT JOIN areas a ON a.id = u.area_id
WHERE DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
ORDER BY s.created_at DESC;

-- 3. Check users structure (promotor with sator)
SELECT 
  u.id,
  u.full_name,
  u.role,
  u.area_id,
  a.name as area_name,
  u.sator_id,
  sator.full_name as sator_name
FROM users u
LEFT JOIN areas a ON a.id = u.area_id
LEFT JOIN users sator ON sator.id = u.sator_id
WHERE u.role IN ('promotor', 'sator', 'spv')
ORDER BY u.role, u.full_name;

-- 4. Test function with a real user ID (replace with actual user ID)
-- Get a promotor user ID first
DO $$
DECLARE
  v_user_id UUID;
  v_result JSONB;
BEGIN
  -- Get first promotor user
  SELECT id INTO v_user_id
  FROM users
  WHERE role = 'promotor'
  LIMIT 1;
  
  IF v_user_id IS NOT NULL THEN
    RAISE NOTICE 'Testing with user ID: %', v_user_id;
    
    -- Call function
    SELECT get_leaderboard_feed(v_user_id, CURRENT_DATE)
    INTO v_result;
    
    RAISE NOTICE 'Result: %', v_result;
  ELSE
    RAISE NOTICE 'No promotor user found';
  END IF;
END $$;
