-- ============================================
-- TEST: Bonus Ratio 2:1 System
-- Untuk produk Y02, Y03T, Y04S
-- ============================================

-- STEP 1: Cek apakah ada bonus rules untuk produk ratio 2:1
SELECT 
  'Bonus Rules - Ratio 2:1' as check_type,
  br.id,
  p.model_name as product_name,
  br.bonus_type,
  br.ratio_value,
  br.bonus_official,
  br.bonus_training
FROM bonus_rules br
JOIN products p ON p.id = br.product_id
WHERE br.bonus_type = 'ratio'
ORDER BY p.model_name;

-- STEP 2: Cek apakah produk Y02, Y03T, Y04S ada di database
SELECT 
  'Products Check' as check_type,
  id,
  model_name
FROM products
WHERE model_name IN ('Y02', 'Y03T', 'Y04S')
ORDER BY model_name;

-- STEP 3: Simulasi perhitungan bonus ratio 2:1
-- Contoh: Promotor jual Y02
DO $$
DECLARE
  test_product_id UUID;
  test_promotor_id UUID;
  test_variant_id UUID;
  test_store_id UUID;
  ratio_value INT;
  bonus_per_unit INT;
BEGIN
  -- Ambil product Y02
  SELECT id INTO test_product_id
  FROM products
  WHERE model_name = 'Y02'
  LIMIT 1;
  
  IF test_product_id IS NULL THEN
    RAISE NOTICE '❌ Product Y02 not found';
    RETURN;
  END IF;
  
  -- Ambil variant Y02
  SELECT id INTO test_variant_id
  FROM product_variants
  WHERE product_id = test_product_id
  LIMIT 1;
  
  -- Ambil promotor official pertama
  SELECT id INTO test_promotor_id
  FROM users
  WHERE role = 'promotor' AND promotor_type = 'official'
  LIMIT 1;
  
  -- Ambil store pertama
  SELECT id INTO test_store_id
  FROM stores
  LIMIT 1;
  
  -- Cek bonus rule
  SELECT ratio_value, bonus_official INTO ratio_value, bonus_per_unit
  FROM bonus_rules
  WHERE bonus_type = 'ratio' AND product_id = test_product_id;
  
  IF NOT FOUND THEN
    RAISE NOTICE '❌ No ratio bonus rule found for Y02';
    RAISE NOTICE 'Creating sample ratio bonus rule...';
    
    INSERT INTO bonus_rules (
      bonus_type,
      product_id,
      ratio_value,
      bonus_official,
      bonus_training
    ) VALUES (
      'ratio',
      test_product_id,
      2,  -- 2:1 ratio
      5000,  -- Rp 5.000 untuk official
      4000   -- Rp 4.000 untuk training
    );
    
    ratio_value := 2;
    bonus_per_unit := 5000;
    
    RAISE NOTICE '✅ Created ratio bonus rule: 2:1, Official: Rp 5.000, Training: Rp 4.000';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '=== SIMULATION: Bonus Ratio 2:1 ===';
  RAISE NOTICE 'Product: Y02';
  RAISE NOTICE 'Ratio: %:1', ratio_value;
  RAISE NOTICE 'Bonus per unit (after ratio): Rp %', bonus_per_unit;
  RAISE NOTICE '';
  RAISE NOTICE 'Expected Results:';
  RAISE NOTICE '- Unit 1: Rp 0 (belum genap % unit)', ratio_value;
  RAISE NOTICE '- Unit 2: Rp % (genap % unit, dapat bonus)', bonus_per_unit, ratio_value;
  RAISE NOTICE '- Unit 3: Rp 0 (belum genap % unit)', ratio_value;
  RAISE NOTICE '- Unit 4: Rp % (genap % unit, dapat bonus)', bonus_per_unit, ratio_value;
  RAISE NOTICE '- Unit 5: Rp 0 (belum genap % unit)', ratio_value;
  RAISE NOTICE '- Unit 6: Rp % (genap % unit, dapat bonus)', bonus_per_unit, ratio_value;
  
END $$;

-- STEP 4: Cek sales Y02/Y03T/Y04S yang sudah ada
SELECT 
  'Existing Sales - Ratio Products' as check_type,
  p.model_name,
  u.full_name as promotor_name,
  u.promotor_type,
  COUNT(*) as total_units,
  FLOOR(COUNT(*) / 2) as bonus_units,
  SUM(so.estimated_bonus) as total_bonus_received,
  FLOOR(COUNT(*) / 2) * 5000 as expected_bonus_official,
  FLOOR(COUNT(*) / 2) * 4000 as expected_bonus_training
FROM sales_sell_out so
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
JOIN users u ON u.id = so.promotor_id
WHERE p.model_name IN ('Y02', 'Y03T', 'Y04S')
GROUP BY p.model_name, u.full_name, u.promotor_type, u.id
ORDER BY p.model_name, u.full_name;

-- STEP 5: Detail per unit untuk debugging
SELECT 
  'Sales Detail - Y02 Example' as check_type,
  so.transaction_date,
  p.model_name,
  u.full_name as promotor_name,
  ROW_NUMBER() OVER (
    PARTITION BY so.promotor_id, p.id 
    ORDER BY so.transaction_date
  ) as unit_number,
  so.estimated_bonus,
  CASE 
    WHEN ROW_NUMBER() OVER (
      PARTITION BY so.promotor_id, p.id 
      ORDER BY so.transaction_date
    ) % 2 = 0 THEN 'Should get bonus'
    ELSE 'No bonus (odd unit)'
  END as expected_result
FROM sales_sell_out so
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
JOIN users u ON u.id = so.promotor_id
WHERE p.model_name IN ('Y02', 'Y03T', 'Y04S')
ORDER BY so.promotor_id, p.id, so.transaction_date
LIMIT 20;

-- STEP 6: Summary check
SELECT 
  'Summary Check' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM bonus_rules 
      WHERE bonus_type = 'ratio'
    ) THEN '✅ Ratio bonus rules exist'
    ELSE '❌ No ratio bonus rules found'
  END as ratio_rules_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM products 
      WHERE model_name IN ('Y02', 'Y03T', 'Y04S')
    ) THEN '✅ Ratio products exist'
    ELSE '❌ No ratio products found'
  END as products_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM sales_sell_out so
      JOIN product_variants pv ON pv.id = so.variant_id
      JOIN products p ON p.id = pv.product_id
      WHERE p.model_name IN ('Y02', 'Y03T', 'Y04S')
    ) THEN '✅ Sales data exists'
    ELSE '⚠️  No sales data yet'
  END as sales_status;
