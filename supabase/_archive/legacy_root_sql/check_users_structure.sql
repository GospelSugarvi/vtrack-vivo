-- Cek struktur tabel users
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'users'
ORDER BY ordinal_position;

-- Cek bagaimana relasi promotor ke store
SELECT 
  'Promotor Store Relation' as check_type,
  u.full_name as promotor_name,
  s.store_name,
  hsp.sator_id
FROM users u
LEFT JOIN stores s ON s.id = u.id -- coba berbagai kemungkinan
LEFT JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = u.id AND hsp.active = true
WHERE u.role = 'promotor'
LIMIT 5;

-- Cek struktur hierarchy_sator_promotor
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'hierarchy_sator_promotor'
ORDER BY ordinal_position;

-- Cek data imei_normalizations untuk lihat relasi
SELECT 
  in2.id,
  in2.promotor_id,
  in2.store_id,
  p.full_name as promotor_name,
  s.store_name
FROM imei_normalizations in2
JOIN users p ON p.id = in2.promotor_id
JOIN stores s ON s.id = in2.store_id
LIMIT 5;
