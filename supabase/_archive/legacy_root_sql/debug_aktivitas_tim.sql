-- =====================================================
-- DEBUG AKTIVITAS TIM - Step by Step
-- =====================================================

-- STEP 1: Cek user SATOR yang login (ganti dengan user_id Antonio)
SELECT id, full_name, role, area
FROM users
WHERE role = 'sator'
ORDER BY full_name;

-- STEP 2: Cek hierarchy - apakah ada promotor di bawah SATOR ini?
-- Ganti 'SATOR_USER_ID' dengan ID Antonio dari query di atas
SELECT 
  hsp.sator_id,
  s.full_name as sator_name,
  hsp.promotor_id,
  p.full_name as promotor_name,
  hsp.active
FROM hierarchy_sator_promotor hsp
INNER JOIN users s ON hsp.sator_id = s.id
INNER JOIN users p ON hsp.promotor_id = p.id
WHERE hsp.sator_id = 'SATOR_USER_ID' -- GANTI INI
ORDER BY p.full_name;

-- STEP 3: Cek assignment promotor ke toko
-- Ganti 'SATOR_USER_ID' dengan ID Antonio
SELECT 
  u.full_name as promotor_name,
  st.store_name,
  aps.active
FROM assignments_promotor_store aps
INNER JOIN users u ON aps.promotor_id = u.id
INNER JOIN stores st ON aps.store_id = st.id
WHERE aps.promotor_id IN (
  SELECT promotor_id 
  FROM hierarchy_sator_promotor 
  WHERE sator_id = 'SATOR_USER_ID' -- GANTI INI
  AND active = true
)
ORDER BY st.store_name, u.full_name;

-- STEP 4: Cek aktivitas promotor hari ini
-- Ganti 'SATOR_USER_ID' dengan ID Antonio
WITH promotor_ids AS (
  SELECT promotor_id 
  FROM hierarchy_sator_promotor
  WHERE sator_id = 'SATOR_USER_ID' -- GANTI INI
  AND active = true
)
SELECT 
  u.full_name as promotor_name,
  
  -- Cek clock in
  EXISTS(
    SELECT 1 FROM attendance_logs al 
    WHERE al.user_id = u.id 
    AND DATE(al.clock_in AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
  ) as has_clock_in,
  
  -- Cek sell out
  EXISTS(
    SELECT 1 FROM sell_out s 
    WHERE s.promotor_id = u.id 
    AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
  ) as has_sell_out,
  
  -- Cek stock input
  EXISTS(
    SELECT 1 FROM stock_movement_log sm 
    WHERE sm.promotor_id = u.id 
    AND DATE(sm.created_at AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
  ) as has_stock_input,
  
  -- Cek promotion
  EXISTS(
    SELECT 1 FROM promotion_reports pr 
    WHERE pr.user_id = u.id 
    AND DATE(pr.created_at AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
  ) as has_promotion,
  
  -- Cek follower
  EXISTS(
    SELECT 1 FROM follower_reports fr 
    WHERE fr.user_id = u.id 
    AND DATE(fr.created_at AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
  ) as has_follower

FROM users u
WHERE u.id IN (SELECT promotor_id FROM promotor_ids)
ORDER BY u.full_name;

-- STEP 5: Test function langsung
-- Ganti 'SATOR_USER_ID' dengan ID Antonio
SELECT get_sator_aktivitas_tim(
  'SATOR_USER_ID'::uuid, -- GANTI INI
  CURRENT_DATE
);

-- STEP 6: Cek apakah tabel hierarchy_sator_promotor ada data
SELECT COUNT(*) as total_hierarchy
FROM hierarchy_sator_promotor
WHERE active = true;

-- STEP 7: Cek struktur tabel hierarchy_sator_promotor
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'hierarchy_sator_promotor'
ORDER BY ordinal_position;
