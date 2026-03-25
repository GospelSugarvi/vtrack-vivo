-- =====================================================
-- CHECK SATOR TABLES - Verification Script
-- Run this after applying migrations
-- =====================================================

-- 1. Check all SATOR-related tables exist
SELECT 
  table_name,
  CASE WHEN table_name IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END as status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
  'sator_monthly_kpi',
  'sator_rewards',
  'warehouse_stock',
  'schedule_requests',
  'sell_in',
  'orders',
  'order_items',
  'store_visits',
  'store_issues',
  'activity_feed',
  'imei_records',
  'stock_validations',
  'hierarchy_sator_promotor',
  'promotion_reports',
  'follower_reports',
  'allbrand_reports'
)
ORDER BY table_name;

-- 2. Check hierarchy tables for SATOR integration
SELECT 
  'hierarchy_sator_promotor' as table_name,
  COUNT(*) as record_count,
  COUNT(CASE WHEN active = true THEN 1 END) as active_count
FROM hierarchy_sator_promotor;

-- 3. Check if RLS is enabled on new tables
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public'
AND tablename IN (
  'sator_monthly_kpi',
  'sator_rewards',
  'warehouse_stock',
  'schedule_requests',
  'sell_in',
  'orders',
  'store_visits',
  'store_issues',
  'activity_feed',
  'imei_records',
  'stock_validations'
)
ORDER BY tablename;

-- 4. Check columns in key tables
SELECT 
  'sator_monthly_kpi' as table_name,
  string_agg(column_name, ', ' ORDER BY ordinal_position) as columns
FROM information_schema.columns 
WHERE table_name = 'sator_monthly_kpi'
UNION ALL
SELECT 
  'schedule_requests' as table_name,
  string_agg(column_name, ', ' ORDER BY ordinal_position) as columns
FROM information_schema.columns 
WHERE table_name = 'schedule_requests'
UNION ALL
SELECT 
  'sell_in' as table_name,
  string_agg(column_name, ', ' ORDER BY ordinal_position) as columns
FROM information_schema.columns 
WHERE table_name = 'sell_in'
UNION ALL
SELECT 
  'store_visits' as table_name,
  string_agg(column_name, ', ' ORDER BY ordinal_position) as columns
FROM information_schema.columns 
WHERE table_name = 'store_visits';

-- 5. Count users by role
SELECT 
  role,
  COUNT(*) as count
FROM users
WHERE deleted_at IS NULL
GROUP BY role
ORDER BY role;

-- 6. Check SATOR users and their promotor count
SELECT 
  u.id,
  u.full_name,
  u.area,
  (SELECT COUNT(*) FROM hierarchy_sator_promotor hsp WHERE hsp.sator_id = u.id AND hsp.active = true) as promotor_count
FROM users u
WHERE u.role = 'sator'
AND u.deleted_at IS NULL
ORDER BY u.full_name;
