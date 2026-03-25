-- =====================================================
-- FIX AKTIVITAS TIM - ANTONIO
-- =====================================================

-- STEP 1: Populate hierarchy_sator_promotor jika belum ada data
INSERT INTO hierarchy_sator_promotor (sator_id, promotor_id, active, created_at)
SELECT DISTINCT
  ass.sator_id,
  aps.promotor_id,
  true as active,
  NOW() as created_at
FROM assignments_sator_store ass
INNER JOIN assignments_promotor_store aps ON ass.store_id = aps.store_id
WHERE ass.active = true 
  AND aps.active = true
  AND NOT EXISTS (
    SELECT 1 FROM hierarchy_sator_promotor hsp
    WHERE hsp.sator_id = ass.sator_id
      AND hsp.promotor_id = aps.promotor_id
  )
ON CONFLICT DO NOTHING;

-- STEP 2: Cek hasil untuk Antonio
SELECT 
  s.full_name as sator_name,
  COUNT(DISTINCT hsp.promotor_id) as promotor_count,
  COUNT(DISTINCT ass.store_id) as store_count
FROM users s
LEFT JOIN hierarchy_sator_promotor hsp ON s.id = hsp.sator_id AND hsp.active = true
LEFT JOIN assignments_sator_store ass ON s.id = ass.sator_id AND ass.active = true
WHERE s.id = 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb' -- Antonio
GROUP BY s.id, s.full_name;

-- STEP 3: Detail promotor di bawah Antonio
SELECT 
  p.full_name as promotor_name,
  st.store_name,
  hsp.active
FROM hierarchy_sator_promotor hsp
INNER JOIN users p ON hsp.promotor_id = p.id
LEFT JOIN assignments_promotor_store aps ON p.id = aps.promotor_id AND aps.active = true
LEFT JOIN stores st ON aps.store_id = st.id
WHERE hsp.sator_id = 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb' -- Antonio
  AND hsp.active = true
ORDER BY p.full_name, st.store_name;

-- STEP 4: Cek aktivitas promotor hari ini untuk Antonio
WITH promotor_ids AS (
  SELECT promotor_id 
  FROM hierarchy_sator_promotor
  WHERE sator_id = 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb' -- Antonio
  AND active = true
)
SELECT 
  u.full_name as promotor_name,
  
  -- Cek clock in (TABEL: attendance)
  EXISTS(
    SELECT 1 FROM attendance a 
    WHERE a.user_id = u.id 
    AND DATE(a.clock_in AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
  ) as has_clock_in,
  
  -- Cek sell out (TABEL: sales_sell_out)
  EXISTS(
    SELECT 1 FROM sales_sell_out s 
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

-- STEP 5: Test function untuk Antonio
SELECT get_sator_aktivitas_tim(
  'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'::uuid, -- Antonio
  CURRENT_DATE
);

-- STEP 6: Cek apakah ada data sell_out hari ini dari promotor Antonio
SELECT 
  u.full_name as promotor_name,
  COUNT(*) as sales_count,
  SUM(s.quantity) as total_units
FROM sell_out s
INNER JOIN users u ON s.promotor_id = u.id
INNER JOIN hierarchy_sator_promotor hsp ON u.id = hsp.promotor_id
WHERE hsp.sator_id = 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb' -- Antonio
  AND hsp.active = true
  AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
GROUP BY u.id, u.full_name
ORDER BY u.full_name;

-- STEP 7: Cek attendance hari ini
SELECT 
  u.full_name as promotor_name,
  al.clock_in,
  al.clock_out
FROM attendance_logs al
INNER JOIN users u ON al.user_id = u.id
INNER JOIN hierarchy_sator_promotor hsp ON u.id = hsp.promotor_id
WHERE hsp.sator_id = 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb' -- Antonio
  AND hsp.active = true
  AND DATE(al.clock_in AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
ORDER BY u.full_name;
