-- ============================================
-- TEST: Ratio 2:1 Calculation
-- Simulasi penjualan Y04S untuk test bonus
-- ============================================

-- STEP 1: Cek data yang ada
SELECT 
  '1. Current Ratio Products' as test_step,
  p.model_name,
  br.ratio_value,
  br.bonus_official,
  br.bonus_training
FROM bonus_rules br
JOIN products p ON p.id = br.product_id
WHERE br.bonus_type = 'ratio'
ORDER BY p.model_name;

-- STEP 2: Cek sales Y04S yang sudah ada (jika ada)
SELECT 
  '2. Existing Y04S Sales' as test_step,
  u.full_name as promotor_name,
  u.promotor_type,
  COUNT(*) as total_units,
  FLOOR(COUNT(*) / 2) as expected_bonus_units,
  SUM(so.estimated_bonus) as actual_bonus_received,
  FLOOR(COUNT(*) / 2) * 5000 as expected_bonus_official,
  FLOOR(COUNT(*) / 2) * 4000 as expected_bonus_training
FROM sales_sell_out so
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
JOIN users u ON u.id = so.promotor_id
WHERE p.model_name = 'Y04S'
GROUP BY u.full_name, u.promotor_type, u.id
ORDER BY u.full_name;

-- STEP 3: Detail per unit untuk melihat pattern bonus
SELECT 
  '3. Y04S Sales Detail (Unit by Unit)' as test_step,
  DATE(so.transaction_date) as sale_date,
  u.full_name as promotor_name,
  ROW_NUMBER() OVER (
    PARTITION BY so.promotor_id, p.id, DATE_TRUNC('month', so.transaction_date)
    ORDER BY so.transaction_date
  ) as unit_number_in_month,
  so.estimated_bonus,
  CASE 
    WHEN ROW_NUMBER() OVER (
      PARTITION BY so.promotor_id, p.id, DATE_TRUNC('month', so.transaction_date)
      ORDER BY so.transaction_date
    ) % 2 = 0 THEN '✅ Should get bonus (even unit)'
    ELSE '❌ No bonus (odd unit)'
  END as expected_result,
  CASE 
    WHEN so.estimated_bonus > 0 THEN '✅ Got bonus'
    ELSE '❌ No bonus'
  END as actual_result
FROM sales_sell_out so
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
JOIN users u ON u.id = so.promotor_id
WHERE p.model_name = 'Y04S'
ORDER BY so.promotor_id, so.transaction_date
LIMIT 20;

-- STEP 4: Check if trigger function is correct
SELECT 
  '4. Trigger Function Check' as test_step,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.routines 
      WHERE routine_name = 'process_sell_out_insert'
    ) THEN '✅ Function exists'
    ELSE '❌ Function not found'
  END as function_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.triggers 
      WHERE trigger_name = 'trigger_sell_out_process'
    ) THEN '✅ Trigger active'
    ELSE '❌ Trigger not found'
  END as trigger_status;

-- STEP 5: Simulation - What would happen if we sell Y04S now?
DO $$
DECLARE
  test_promotor_id UUID;
  test_variant_id UUID;
  test_store_id UUID;
  current_month_sales INT;
  next_unit_number INT;
  expected_bonus INT;
BEGIN
  -- Get a promotor
  SELECT id INTO test_promotor_id
  FROM users
  WHERE role = 'promotor' AND promotor_type = 'official'
  LIMIT 1;
  
  -- Get Y04S variant
  SELECT pv.id INTO test_variant_id
  FROM product_variants pv
  JOIN products p ON p.id = pv.product_id
  WHERE p.model_name = 'Y04S'
  LIMIT 1;
  
  -- Get a store
  SELECT id INTO test_store_id
  FROM stores
  LIMIT 1;
  
  IF test_promotor_id IS NULL OR test_variant_id IS NULL OR test_store_id IS NULL THEN
    RAISE NOTICE '⚠️  Missing test data (promotor, variant, or store)';
    RETURN;
  END IF;
  
  -- Count current month sales
  SELECT COUNT(*) INTO current_month_sales
  FROM sales_sell_out so
  JOIN product_variants pv ON pv.id = so.variant_id
  JOIN products p ON p.id = pv.product_id
  WHERE so.promotor_id = test_promotor_id
    AND p.model_name = 'Y04S'
    AND so.transaction_date >= DATE_TRUNC('month', NOW());
  
  next_unit_number := current_month_sales + 1;
  
  -- Calculate expected bonus
  IF next_unit_number % 2 = 0 THEN
    expected_bonus := 5000; -- Official gets 5000
  ELSE
    expected_bonus := 0;
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '=== SIMULATION ===';
  RAISE NOTICE 'If promotor sells Y04S now:';
  RAISE NOTICE '- Current month sales: % units', current_month_sales;
  RAISE NOTICE '- Next unit will be: Unit #%', next_unit_number;
  RAISE NOTICE '- Expected bonus: Rp %', expected_bonus;
  RAISE NOTICE '- Reason: % % 2 = %', next_unit_number, next_unit_number, next_unit_number % 2;
  
  IF expected_bonus > 0 THEN
    RAISE NOTICE '✅ This unit WILL GET bonus (even number)';
  ELSE
    RAISE NOTICE '❌ This unit will NOT get bonus (odd number)';
  END IF;
END $$;

-- STEP 6: Final Summary
SELECT 
  '5. Final Summary' as test_step,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM bonus_rules br
      JOIN products p ON p.id = br.product_id
      WHERE br.bonus_type = 'ratio' AND p.model_name = 'Y04S'
    ) THEN '✅ Y04S configured in bonus_rules'
    ELSE '❌ Y04S not configured'
  END as y04s_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM bonus_rules br
      JOIN products p ON p.id = br.product_id
      WHERE br.bonus_type = 'ratio' AND br.ratio_value = 2
    ) THEN '✅ Ratio 2:1 configured'
    ELSE '❌ Ratio not configured'
  END as ratio_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM sales_sell_out so
      JOIN product_variants pv ON pv.id = so.variant_id
      JOIN products p ON p.id = pv.product_id
      WHERE p.model_name = 'Y04S'
    ) THEN '✅ Has sales data'
    ELSE '⚠️  No sales data yet'
  END as sales_status;
