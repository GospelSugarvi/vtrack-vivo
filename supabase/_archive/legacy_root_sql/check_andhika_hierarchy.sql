-- Cek hierarchy untuk ANDHIKA ULLY
SELECT 
  'Andhika Hierarchy' as check_type,
  p.full_name as promotor_name,
  p.id as promotor_id,
  s.full_name as sator_name,
  s.id as sator_id,
  hsp.active as is_active
FROM users p
LEFT JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = p.id
LEFT JOIN users s ON s.id = hsp.sator_id
WHERE p.full_name ILIKE '%andhika%'
ORDER BY hsp.active DESC NULLS LAST;

-- Cek semua sator yang ada
SELECT 
  'All Sators' as check_type,
  id,
  full_name,
  role
FROM users
WHERE role = 'sator'
ORDER BY full_name;

-- Cek semua hierarchy yang aktif
SELECT 
  'Active Hierarchies' as check_type,
  s.full_name as sator_name,
  p.full_name as promotor_name,
  hsp.active
FROM hierarchy_sator_promotor hsp
JOIN users s ON s.id = hsp.sator_id
JOIN users p ON p.id = hsp.promotor_id
WHERE hsp.active = true
ORDER BY s.full_name, p.full_name;
