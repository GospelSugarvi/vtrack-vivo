-- ============================================
-- FIX ALL BONUS ISSUES
-- ============================================

-- ISSUE 1: Update Y04S ratio_val di products table (untuk konsistensi)
UPDATE products
SET ratio_val = 2, updated_at = NOW()
WHERE model_name = 'Y04S' AND bonus_type = 'ratio';

-- ISSUE 2: Fix range bonus yang salah (Training 70000 -> 7000)
UPDATE bonus_rules
SET 
  bonus_training = 7000,
  updated_at = NOW()
WHERE id = '3ef2e4e8-4a16-4085-abd2-8bbd6aabed74'
  AND bonus_type = 'range'
  AND min_price = 1599000;

-- ISSUE 3: Tambah Y02 dan Y03T ke bonus_rules (jika produk ada)
DO $$
DECLARE
  y02_id UUID;
  y03t_id UUID;
BEGIN
  -- Get product IDs
  SELECT id INTO y02_id FROM products WHERE model_name = 'Y02' LIMIT 1;
  SELECT id INTO y03t_id FROM products WHERE model_name = 'Y03T' LIMIT 1;
  
  -- Add Y02 if exists
  IF y02_id IS NOT NULL THEN
    INSERT INTO bonus_rules (
      bonus_type,
      product_id,
      ratio_value,
      bonus_official,
      bonus_training
    ) VALUES (
      'ratio',
      y02_id,
      2,
      5000,
      4000
    )
    ON CONFLICT DO NOTHING;
    
    RAISE NOTICE '✅ Y02 added to bonus_rules';
  ELSE
    RAISE NOTICE '⚠️  Y02 product not found in products table';
  END IF;
  
  -- Add Y03T if exists
  IF y03t_id IS NOT NULL THEN
    INSERT INTO bonus_rules (
      bonus_type,
      product_id,
      ratio_value,
      bonus_official,
      bonus_training
    ) VALUES (
      'ratio',
      y03t_id,
      2,
      5000,
      4000
    )
    ON CONFLICT DO NOTHING;
    
    RAISE NOTICE '✅ Y03T added to bonus_rules';
  ELSE
    RAISE NOTICE '⚠️  Y03T product not found in products table';
  END IF;
END $$;

-- ISSUE 4: Update Y02 dan Y03T di products table juga (untuk konsistensi)
UPDATE products
SET 
  bonus_type = 'ratio',
  ratio_val = 2,
  updated_at = NOW()
WHERE model_name IN ('Y02', 'Y03T');

-- VERIFICATION
SELECT 
  '=== VERIFICATION ===' as status;

-- Check ratio products in bonus_rules
SELECT 
  'Ratio Products in bonus_rules' as check_type,
  p.model_name,
  br.ratio_value,
  br.bonus_official,
  br.bonus_training
FROM bonus_rules br
JOIN products p ON p.id = br.product_id
WHERE br.bonus_type = 'ratio'
ORDER BY p.model_name;

-- Check range bonus yang sudah difix
SELECT 
  'Fixed Range Bonus' as check_type,
  min_price,
  max_price,
  bonus_official,
  bonus_training
FROM bonus_rules
WHERE bonus_type = 'range'
  AND min_price = 1599000;

-- Summary
SELECT 
  'Summary' as check_type,
  COUNT(CASE WHEN bonus_type = 'ratio' THEN 1 END) as ratio_count,
  COUNT(CASE WHEN bonus_type = 'flat' THEN 1 END) as flat_count,
  COUNT(CASE WHEN bonus_type = 'range' THEN 1 END) as range_count,
  COUNT(*) as total_rules
FROM bonus_rules;
