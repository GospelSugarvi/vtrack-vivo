-- ============================================
-- AUDIT LENGKAP: Sistem Bonus Ratio 2:1
-- Cek database, trigger, dan data integrity
-- ============================================

-- 1. CEK TABEL BONUS_RULES
SELECT '=== 1. BONUS RULES TABLE ===' as section;
SELECT 
  'Bonus Rules' as check_type,
  br.bonus_type,
  p.model_name,
  br.ratio_value,
  br.bonus_official,
  br.bonus_training,
  br.created_at
FROM bonus_rules br
LEFT JOIN products p ON p.id = br.product_id
ORDER BY br.bonus_type, p.model_name;

-- 2. CEK TRIGGER FUNCTION
SELECT '=== 2. TRIGGER FUNCTION ===' as section;
SELECT 
  'Trigger Check' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.routines 
      WHERE routine_name = 'process_sell_out_insert'
      AND routine_type = 'FUNCTION'
    ) THEN '✅ Function exists'
    ELSE '❌ Function NOT found'
  END as function_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.triggers 
      WHERE trigger_name = 'trigger_sell_out_process'
      AND event_object_table = 'sales_sell_out'
    ) THEN '✅ Trigger active'
    ELSE '❌ Trigger NOT active'
  END as trigger_status;

-- 3. CEK SALES DENGAN BONUS RATIO (Detail per unit)
SELECT '=== 3. SALES WITH RATIO BONUS ===' as section;
SELECT 
  'Sales Detail' as check_type,
  DATE(so.transaction_date) as sale_date,
  u.full_name as promotor_name,
  u.promotor_type,
  p.model_name,
  so.price_at_transaction,
  so.estimated_bonus,
  -- Hitung unit ke berapa dalam bulan ini
  ROW_NUMBER() OVER (
    PARTITION BY so.promotor_id, p.id, DATE_TRUNC('month', so.transaction_date)
    ORDER BY so.transaction_date
  ) as unit_number,
  CASE 
    WHEN ROW_NUMBER() OVER (
      PARTITION BY so.promotor_id, p.id, DATE_TRUNC('month', so.transaction_date)
      ORDER BY so.transaction_date
    ) % 2 = 0 THEN '✅ Should get bonus (even)'
    ELSE '❌ No bonus (odd)'
  END as expected_result,
  CASE 
    WHEN so.estimated_bonus > 0 THEN '✅ Got bonus'
    ELSE '❌ No bonus'
  END as actual_result,
  CASE 
    WHEN (
      ROW_NUMBER() OVER (
        PARTITION BY so.promotor_id, p.id, DATE_TRUNC('month', so.transaction_date)
        ORDER BY so.transaction_date
      ) % 2 = 0 AND so.estimated_bonus > 0
    ) OR (
      ROW_NUMBER() OVER (
        PARTITION BY so.promotor_id, p.id, DATE_TRUNC('month', so.transaction_date)
        ORDER BY so.transaction_date
      ) % 2 = 1 AND so.estimated_bonus = 0
    ) THEN '✅ CORRECT'
    ELSE '❌ WRONG'
  END as validation
FROM sales_sell_out so
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
JOIN users u ON u.id = so.promotor_id
WHERE p.id IN (
  SELECT product_id FROM bonus_rules WHERE bonus_type = 'ratio'
)
ORDER BY so.promotor_id, p.id, so.transaction_date
LIMIT 50;

-- 4. CEK DASHBOARD METRICS
SELECT '=== 4. DASHBOARD METRICS ===' as section;
SELECT 
  'Dashboard Data' as check_type,
  u.full_name as promotor_name,
  tp.period_name,
  dpm.total_omzet_real,
  dpm.total_units_sold,
  dpm.total_units_focus,
  dpm.estimated_bonus_total as bonus_in_dashboard,
  -- Compare dengan raw sales
  (SELECT COALESCE(SUM(so.estimated_bonus), 0)
   FROM sales_sell_out so
   WHERE so.promotor_id = dpm.user_id
   AND so.transaction_date >= tp.start_date
   AND so.transaction_date <= tp.end_date) as bonus_from_raw_sales,
  CASE 
    WHEN dpm.estimated_bonus_total = (
      SELECT COALESCE(SUM(so.estimated_bonus), 0)
      FROM sales_sell_out so
      WHERE so.promotor_id = dpm.user_id
      AND so.transaction_date >= tp.start_date
      AND so.transaction_date <= tp.end_date
    ) THEN '✅ MATCH'
    ELSE '❌ MISMATCH'
  END as data_integrity
FROM dashboard_performance_metrics dpm
JOIN users u ON u.id = dpm.user_id
JOIN target_periods tp ON tp.id = dpm.period_id
WHERE dpm.estimated_bonus_total > 0
ORDER BY u.full_name, tp.start_date DESC;

-- 5. CEK KOLOM DASHBOARD
SELECT '=== 5. DASHBOARD STRUCTURE ===' as section;
SELECT 
  'Column Check' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'dashboard_performance_metrics'
      AND column_name = 'estimated_bonus_total'
    ) THEN '✅ Column exists'
    ELSE '❌ Column NOT found'
  END as bonus_column_status;

-- 6. SUMMARY & VALIDATION
SELECT '=== 6. FINAL SUMMARY ===' as section;
SELECT 
  'System Health' as check_type,
  (SELECT COUNT(*) FROM bonus_rules WHERE bonus_type = 'ratio') as ratio_products_configured,
  (SELECT COUNT(*) FROM sales_sell_out WHERE estimated_bonus > 0) as total_sales_with_bonus,
  (SELECT SUM(estimated_bonus) FROM sales_sell_out) as total_bonus_all_time,
  (SELECT SUM(estimated_bonus_total) FROM dashboard_performance_metrics) as total_bonus_in_dashboard,
  CASE 
    WHEN (SELECT SUM(estimated_bonus) FROM sales_sell_out) = 
         (SELECT SUM(estimated_bonus_total) FROM dashboard_performance_metrics)
    THEN '✅ DATA INTEGRITY OK'
    ELSE '⚠️ DATA MISMATCH - Need recalculation'
  END as overall_status;

-- 7. CEK LOGIC RATIO (Simulasi)
SELECT '=== 7. RATIO LOGIC TEST ===' as section;
SELECT 
  'Logic Test' as check_type,
  promotor_name,
  product_name,
  total_units,
  expected_bonus_units,
  actual_bonus_units,
  CASE 
    WHEN expected_bonus_units = actual_bonus_units THEN '✅ LOGIC CORRECT'
    ELSE '❌ LOGIC WRONG'
  END as logic_validation
FROM (
  SELECT 
    u.full_name as promotor_name,
    p.model_name as product_name,
    COUNT(*) as total_units,
    FLOOR(COUNT(*) / 2) as expected_bonus_units,
    SUM(CASE WHEN so.estimated_bonus > 0 THEN 1 ELSE 0 END) as actual_bonus_units
  FROM sales_sell_out so
  JOIN product_variants pv ON pv.id = so.variant_id
  JOIN products p ON p.id = pv.product_id
  JOIN users u ON u.id = so.promotor_id
  WHERE p.id IN (SELECT product_id FROM bonus_rules WHERE bonus_type = 'ratio')
  AND DATE_TRUNC('month', so.transaction_date) = DATE_TRUNC('month', NOW())
  GROUP BY u.full_name, p.model_name, u.id, p.id
) subq;

-- 8. CEK PRODUCTS TABLE (Konsistensi)
SELECT '=== 8. PRODUCTS TABLE CONSISTENCY ===' as section;
SELECT 
  'Product Config' as check_type,
  p.model_name,
  p.bonus_type as bonus_type_in_products,
  p.ratio_val as ratio_val_in_products,
  br.bonus_type as bonus_type_in_rules,
  br.ratio_value as ratio_value_in_rules,
  CASE 
    WHEN p.bonus_type = br.bonus_type AND p.ratio_val = br.ratio_value 
    THEN '✅ Consistent'
    WHEN br.id IS NULL THEN '⚠️ Not in bonus_rules'
    ELSE '⚠️ Inconsistent'
  END as consistency_check
FROM products p
LEFT JOIN bonus_rules br ON br.product_id = p.id AND br.bonus_type = 'ratio'
WHERE p.bonus_type = 'ratio' OR br.bonus_type = 'ratio'
ORDER BY p.model_name;
