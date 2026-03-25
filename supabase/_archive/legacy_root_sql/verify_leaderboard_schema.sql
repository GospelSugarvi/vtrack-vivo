-- VERIFY ALL COLUMNS USED IN LEADERBOARD FUNCTION

-- 1. Check users table columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'users' 
  AND column_name IN ('id', 'role', 'area', 'full_name', 'promotor_type')
ORDER BY column_name;

-- 2. Check sales_sell_out table columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_sell_out' 
  AND column_name IN ('id', 'promotor_id', 'estimated_bonus', 'bonus', 'created_at')
ORDER BY column_name;

-- 3. Check hierarchy_sator_promotor table exists and columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'hierarchy_sator_promotor' 
  AND column_name IN ('id', 'sator_id', 'promotor_id', 'active')
ORDER BY column_name;

-- 4. Check actual data structure
SELECT 
  'users' as table_name,
  COUNT(*) as total_rows,
  COUNT(DISTINCT area) as distinct_areas,
  COUNT(CASE WHEN role = 'promotor' THEN 1 END) as promotor_count,
  COUNT(CASE WHEN role = 'sator' THEN 1 END) as sator_count,
  COUNT(CASE WHEN role = 'spv' THEN 1 END) as spv_count
FROM users;

-- 5. Check sales_sell_out data
SELECT 
  COUNT(*) as total_sales,
  COUNT(DISTINCT promotor_id) as distinct_promotors,
  MIN(created_at) as oldest_sale,
  MAX(created_at) as newest_sale,
  SUM(estimated_bonus) as total_bonus
FROM sales_sell_out;

-- 6. Check hierarchy data
SELECT 
  COUNT(*) as total_relations,
  COUNT(CASE WHEN active = true THEN 1 END) as active_relations
FROM hierarchy_sator_promotor;

-- 7. Sample data check
SELECT 
  u.full_name,
  u.role,
  u.area,
  u.promotor_type
FROM users u
WHERE u.role IN ('promotor', 'sator', 'spv')
LIMIT 5;
