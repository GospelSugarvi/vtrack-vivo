-- ============================================
-- FIX: Y04S Ratio Value dari 1 menjadi 2
-- Masalah: ratio_val = 1, seharusnya 2 (untuk ratio 2:1)
-- ============================================

-- STEP 1: Cek current value
SELECT 
  'Current Y04S Settings' as check_type,
  model_name,
  bonus_type,
  ratio_val,
  flat_bonus
FROM products
WHERE model_name IN ('Y02', 'Y03T', 'Y04S');

-- STEP 2: Update Y04S ratio_val dari 1 ke 2
UPDATE products
SET 
  ratio_val = 2,
  updated_at = NOW()
WHERE model_name = 'Y04S' 
  AND bonus_type = 'ratio';

-- STEP 3: Update Y02 dan Y03T juga (jika ada)
UPDATE products
SET 
  bonus_type = 'ratio',
  ratio_val = 2,
  updated_at = NOW()
WHERE model_name IN ('Y02', 'Y03T');

-- STEP 4: Verify
SELECT 
  'After Update' as check_type,
  model_name,
  bonus_type,
  ratio_val,
  flat_bonus
FROM products
WHERE model_name IN ('Y02', 'Y03T', 'Y04S');

-- STEP 5: Cek apakah ada tabel bonus_rules terpisah
SELECT 
  'Bonus Rules Table Check' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.tables 
      WHERE table_name = 'bonus_rules'
    ) THEN '✅ bonus_rules table exists'
    ELSE '❌ bonus_rules table not found'
  END as status;

-- STEP 6: Jika ada bonus_rules, cek isinya
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'bonus_rules') THEN
    RAISE NOTICE '=== Checking bonus_rules table ===';
    PERFORM * FROM bonus_rules LIMIT 5;
  ELSE
    RAISE NOTICE '⚠️  bonus_rules table does not exist, using products table for bonus config';
  END IF;
END $$;
