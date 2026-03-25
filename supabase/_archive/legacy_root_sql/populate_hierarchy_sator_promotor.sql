-- =====================================================
-- POPULATE HIERARCHY_SATOR_PROMOTOR
-- =====================================================
-- Tabel hierarchy_sator_promotor menghubungkan SATOR dengan PROMOTOR
-- Data ini diisi berdasarkan assignments_sator_store dan assignments_promotor_store

-- STEP 1: Cek data yang ada sekarang
SELECT 
  COUNT(*) as total_existing,
  COUNT(CASE WHEN active = true THEN 1 END) as active_count
FROM hierarchy_sator_promotor;

-- STEP 2: Lihat struktur data yang akan kita buat
-- Logic: Jika SATOR handle toko X, dan promotor Y juga di toko X, 
-- maka SATOR adalah atasan promotor Y
SELECT DISTINCT
  ass.sator_id,
  s.full_name as sator_name,
  aps.promotor_id,
  p.full_name as promotor_name,
  st.store_name,
  ass.active as sator_active,
  aps.active as promotor_active
FROM assignments_sator_store ass
INNER JOIN assignments_promotor_store aps ON ass.store_id = aps.store_id
INNER JOIN users s ON ass.sator_id = s.id
INNER JOIN users p ON aps.promotor_id = p.id
INNER JOIN stores st ON ass.store_id = st.id
WHERE ass.active = true 
  AND aps.active = true
ORDER BY s.full_name, p.full_name;

-- STEP 3: Insert data ke hierarchy_sator_promotor
-- Hanya insert jika belum ada
INSERT INTO hierarchy_sator_promotor (sator_id, promotor_id, active, created_at, updated_at)
SELECT DISTINCT
  ass.sator_id,
  aps.promotor_id,
  true as active,
  NOW() as created_at,
  NOW() as updated_at
FROM assignments_sator_store ass
INNER JOIN assignments_promotor_store aps ON ass.store_id = aps.store_id
WHERE ass.active = true 
  AND aps.active = true
  -- Hanya insert jika belum ada
  AND NOT EXISTS (
    SELECT 1 FROM hierarchy_sator_promotor hsp
    WHERE hsp.sator_id = ass.sator_id
      AND hsp.promotor_id = aps.promotor_id
  )
ON CONFLICT DO NOTHING;

-- STEP 4: Verifikasi hasil
SELECT 
  s.full_name as sator_name,
  COUNT(DISTINCT hsp.promotor_id) as promotor_count,
  COUNT(DISTINCT ass.store_id) as store_count
FROM users s
LEFT JOIN hierarchy_sator_promotor hsp ON s.id = hsp.sator_id AND hsp.active = true
LEFT JOIN assignments_sator_store ass ON s.id = ass.sator_id AND ass.active = true
WHERE s.role = 'sator'
GROUP BY s.id, s.full_name
ORDER BY s.full_name;

-- STEP 5: Detail per SATOR
SELECT 
  s.full_name as sator_name,
  p.full_name as promotor_name,
  hsp.active,
  hsp.created_at
FROM hierarchy_sator_promotor hsp
INNER JOIN users s ON hsp.sator_id = s.id
INNER JOIN users p ON hsp.promotor_id = p.id
ORDER BY s.full_name, p.full_name;
