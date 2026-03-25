-- ============================================
-- VERIFY: IMEI Normalization Fix
-- Quick check setelah menjalankan fix
-- ============================================

-- 1. Cek tabel sator_store_assignments sudah ada
SELECT 
  'Table Check' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables 
      WHERE table_name = 'sator_store_assignments'
    ) THEN '✅ Table exists'
    ELSE '❌ Table missing'
  END as status;

-- 2. Cek jumlah store assignments
SELECT 
  'Store Assignments' as check_type,
  COUNT(*) as total_assignments,
  COUNT(DISTINCT sator_id) as total_sators,
  COUNT(DISTINCT store_id) as total_stores
FROM sator_store_assignments
WHERE is_active = true;

-- 3. Cek detail per sator
SELECT 
  'Assignments per Sator' as check_type,
  u.full_name as sator_name,
  COUNT(DISTINCT ssa.store_id) as assigned_stores,
  STRING_AGG(s.store_name, ', ') as store_names
FROM users u
LEFT JOIN sator_store_assignments ssa ON ssa.sator_id = u.id AND ssa.is_active = true
LEFT JOIN stores s ON s.id = ssa.store_id
WHERE u.role = 'sator'
GROUP BY u.id, u.full_name
ORDER BY u.full_name;

-- 4. Cek IMEI normalizations yang sekarang visible ke sator
SELECT 
  'IMEI Visibility' as check_type,
  u.full_name as sator_name,
  COUNT(DISTINCT in2.id) as visible_imei_count,
  COUNT(DISTINCT CASE WHEN in2.status = 'pending' THEN in2.id END) as pending_count
FROM users u
LEFT JOIN sator_store_assignments ssa ON ssa.sator_id = u.id AND ssa.is_active = true
LEFT JOIN imei_normalizations in2 ON in2.store_id = ssa.store_id
WHERE u.role = 'sator'
GROUP BY u.id, u.full_name
ORDER BY visible_imei_count DESC;

-- 5. Test function get_sator_imei_list
SELECT 
  'Function Test' as check_type,
  u.full_name as sator_name,
  json_array_length(get_sator_imei_list(u.id)) as imei_count
FROM users u
WHERE u.role = 'sator'
ORDER BY u.full_name;

-- 6. Detail IMEI yang sekarang visible
SELECT 
  'IMEI Details' as check_type,
  u.full_name as sator_name,
  s.store_name,
  p.full_name as promotor_name,
  in2.new_imei,
  in2.status,
  in2.created_at
FROM users u
INNER JOIN sator_store_assignments ssa ON ssa.sator_id = u.id AND ssa.is_active = true
INNER JOIN imei_normalizations in2 ON in2.store_id = ssa.store_id
INNER JOIN stores s ON s.id = in2.store_id
INNER JOIN users p ON p.id = in2.promotor_id
WHERE u.role = 'sator'
ORDER BY in2.created_at DESC;
