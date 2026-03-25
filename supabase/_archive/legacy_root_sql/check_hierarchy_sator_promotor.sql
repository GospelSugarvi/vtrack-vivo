-- Cek apakah tabel hierarchy_sator_promotor ada
SELECT EXISTS (
  SELECT FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'hierarchy_sator_promotor'
) as table_exists;

-- Cek struktur tabel
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'hierarchy_sator_promotor'
ORDER BY ordinal_position;

-- Cek isi tabel
SELECT 
  hsp.*,
  s.full_name as sator_name,
  p.full_name as promotor_name
FROM hierarchy_sator_promotor hsp
LEFT JOIN users s ON hsp.sator_id = s.id
LEFT JOIN users p ON hsp.promotor_id = p.id
ORDER BY hsp.created_at DESC
LIMIT 20;

-- Cek total data
SELECT 
  COUNT(*) as total,
  COUNT(CASE WHEN active = true THEN 1 END) as active_count,
  COUNT(CASE WHEN active = false THEN 1 END) as inactive_count
FROM hierarchy_sator_promotor;

-- Cek apakah Antonio punya promotor
SELECT 
  s.full_name as sator_name,
  COUNT(hsp.promotor_id) as promotor_count
FROM users s
LEFT JOIN hierarchy_sator_promotor hsp ON s.id = hsp.sator_id AND hsp.active = true
WHERE s.role = 'sator'
GROUP BY s.id, s.full_name
ORDER BY s.full_name;
