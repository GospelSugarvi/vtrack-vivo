-- ============================================
-- CHECK ALL BONUS RELATED TABLES
-- ============================================

-- 1. Cek tabel products (bonus config ada di sini)
SELECT 
  '1. PRODUCTS TABLE' as section,
  model_name,
  bonus_type,
  ratio_val,
  flat_bonus
FROM products
ORDER BY model_name
LIMIT 20;

-- 2. Cek apakah ada tabel bonus_rules terpisah
SELECT 
  '2. BONUS_RULES TABLE CHECK' as section,
  CASE 
    WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bonus_rules')
    THEN 'EXISTS'
    ELSE 'NOT EXISTS'
  END as table_status;

-- 3. Jika bonus_rules ada, tampilkan strukturnya
SELECT 
  '3. BONUS_RULES STRUCTURE' as section,
  column_name,
  data_type
FROM information_schema.columns
WHERE table_name = 'bonus_rules'
ORDER BY ordinal_position;

-- 4. Jika bonus_rules ada, tampilkan datanya
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bonus_rules') THEN
    RAISE NOTICE '=== BONUS_RULES DATA ===';
  END IF;
END $$;

SELECT 
  '4. BONUS_RULES DATA' as section,
  *
FROM bonus_rules
WHERE 1=1
LIMIT 20;

-- 5. Cek tabel point_ranges (untuk Sator/SPV bonus)
SELECT 
  '5. POINT_RANGES TABLE CHECK' as section,
  CASE 
    WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'point_ranges')
    THEN 'EXISTS'
    ELSE 'NOT EXISTS'
  END as table_status;

-- 6. Cek semua tabel yang ada kata 'bonus' di namanya
SELECT 
  '6. ALL BONUS RELATED TABLES' as section,
  table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND (
    table_name LIKE '%bonus%' 
    OR table_name LIKE '%point%'
    OR table_name LIKE '%reward%'
  )
ORDER BY table_name;

-- 7. Cek kolom bonus di tabel products
SELECT 
  '7. PRODUCTS BONUS COLUMNS' as section,
  column_name,
  data_type,
  column_default
FROM information_schema.columns
WHERE table_name = 'products'
  AND (
    column_name LIKE '%bonus%'
    OR column_name LIKE '%ratio%'
    OR column_name LIKE '%flat%'
  )
ORDER BY ordinal_position;
