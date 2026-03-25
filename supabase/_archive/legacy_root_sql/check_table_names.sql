-- Cek semua tabel yang ada
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
  AND (
    table_name LIKE '%attendance%' OR
    table_name LIKE '%clock%' OR
    table_name LIKE '%sell%' OR
    table_name LIKE '%stock%' OR
    table_name LIKE '%promotion%' OR
    table_name LIKE '%follower%'
  )
ORDER BY table_name;
