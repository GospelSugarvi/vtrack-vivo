-- ============================================
-- CEK: Dashboard Bonus Update
-- Verifikasi bonus ratio 2:1 sudah masuk dashboard
-- ============================================

-- 1. Cek sales Y04S dengan bonus
SELECT 
  '1. Y04S Sales with Bonus' as check_type,
  u.full_name as promotor_name,
  DATE(so.transaction_date) as sale_date,
  p.model_name,
  so.price_at_transaction,
  so.estimated_bonus,
  CASE 
    WHEN so.estimated_bonus > 0 THEN '✅ Got bonus'
    ELSE '❌ No bonus'
  END as bonus_status
FROM sales_sell_out so
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
JOIN users u ON u.id = so.promotor_id
WHERE p.model_name = 'Y04S'
ORDER BY so.promotor_id, so.transaction_date
LIMIT 20;

-- 2. Cek dashboard metrics untuk promotor yang jual Y04S
SELECT 
  '2. Dashboard Metrics (Promotor)' as check_type,
  u.full_name as promotor_name,
  dpm.total_omzet_real,
  dpm.total_units_sold,
  dpm.total_units_focus,
  COALESCE(dpm.estimated_bonus_total, 0) as bonus_in_dashboard,
  tp.period_name,
  dpm.last_updated,
  -- Compare dengan raw data
  (SELECT SUM(so.estimated_bonus) 
   FROM sales_sell_out so 
   WHERE so.promotor_id = u.id 
   AND so.transaction_date >= tp.start_date 
   AND so.transaction_date <= tp.end_date) as bonus_from_raw_sales,
  CASE 
    WHEN COALESCE(dpm.estimated_bonus_total, 0) = (
      SELECT COALESCE(SUM(so.estimated_bonus), 0)
      FROM sales_sell_out so 
      WHERE so.promotor_id = u.id 
      AND so.transaction_date >= tp.start_date 
      AND so.transaction_date <= tp.end_date
    ) THEN '✅ Match'
    ELSE '⚠️ Mismatch'
  END as data_integrity
FROM dashboard_performance_metrics dpm
JOIN users u ON u.id = dpm.user_id
JOIN target_periods tp ON tp.id = dpm.period_id
WHERE u.id IN (
  SELECT DISTINCT so.promotor_id
  FROM sales_sell_out so
  JOIN product_variants pv ON pv.id = so.variant_id
  JOIN products p ON p.id = pv.product_id
  WHERE p.model_name = 'Y04S'
)
ORDER BY u.full_name, tp.start_date DESC
LIMIT 10;

-- 3. Cek total bonus per promotor bulan ini
SELECT 
  '3. Total Bonus This Month' as check_type,
  u.full_name as promotor_name,
  COUNT(*) as total_sales,
  SUM(so.estimated_bonus) as total_bonus_received,
  SUM(CASE WHEN so.estimated_bonus > 0 THEN 1 ELSE 0 END) as sales_with_bonus,
  SUM(CASE WHEN so.estimated_bonus = 0 THEN 1 ELSE 0 END) as sales_no_bonus
FROM sales_sell_out so
JOIN users u ON u.id = so.promotor_id
WHERE so.transaction_date >= DATE_TRUNC('month', NOW())
GROUP BY u.full_name, u.id
HAVING SUM(so.estimated_bonus) > 0
ORDER BY total_bonus_received DESC
LIMIT 10;

-- 4. Cek apakah trigger masih aktif
SELECT 
  '4. Trigger Status' as check_type,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.triggers 
      WHERE trigger_name = 'trigger_sell_out_process'
      AND event_object_table = 'sales_sell_out'
    ) THEN '✅ Trigger aktif'
    ELSE '❌ Trigger tidak aktif'
  END as trigger_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.routines 
      WHERE routine_name = 'process_sell_out_insert'
    ) THEN '✅ Function exists'
    ELSE '❌ Function not found'
  END as function_status;

-- 5. Summary: Bonus system health check
SELECT 
  '5. System Health' as check_type,
  (SELECT COUNT(*) FROM bonus_rules WHERE bonus_type = 'ratio') as ratio_rules_count,
  (SELECT COUNT(*) FROM sales_sell_out WHERE estimated_bonus > 0 AND transaction_date >= DATE_TRUNC('month', NOW())) as sales_with_bonus_this_month,
  (SELECT SUM(estimated_bonus) FROM sales_sell_out WHERE transaction_date >= DATE_TRUNC('month', NOW())) as total_bonus_from_raw_sales,
  (SELECT SUM(estimated_bonus_total) FROM dashboard_performance_metrics) as total_bonus_in_dashboard,
  (SELECT COUNT(DISTINCT promotor_id) FROM sales_sell_out WHERE estimated_bonus > 0) as promotors_with_bonus;
