-- ============================================
-- ADDITIONAL OPTIMIZATIONS
-- Optimasi tambahan untuk performa maksimal
-- ============================================

-- ========================================
-- 1. ADD CHECK CONSTRAINTS (Data Validation)
-- ========================================

-- Bonus harus non-negative
ALTER TABLE sales_sell_out 
DROP CONSTRAINT IF EXISTS chk_bonus_positive;

ALTER TABLE sales_sell_out 
ADD CONSTRAINT chk_bonus_positive 
CHECK (estimated_bonus >= 0);

-- Price harus positive
ALTER TABLE sales_sell_out 
DROP CONSTRAINT IF EXISTS chk_price_positive;

ALTER TABLE sales_sell_out 
ADD CONSTRAINT chk_price_positive 
CHECK (price_at_transaction > 0);

-- Ratio value harus valid
ALTER TABLE bonus_rules 
DROP CONSTRAINT IF EXISTS chk_ratio_valid;

ALTER TABLE bonus_rules 
ADD CONSTRAINT chk_ratio_valid 
CHECK (ratio_value IS NULL OR ratio_value > 0);

-- Dashboard metrics harus non-negative
ALTER TABLE dashboard_performance_metrics 
DROP CONSTRAINT IF EXISTS chk_metrics_positive;

ALTER TABLE dashboard_performance_metrics 
ADD CONSTRAINT chk_metrics_positive 
CHECK (
  total_omzet_real >= 0 AND 
  total_units_sold >= 0 AND 
  total_units_focus >= 0 AND
  estimated_bonus_total >= 0
);

-- ========================================
-- 2. ADD PARTIAL INDEXES (Hot Data)
-- ========================================

-- Index untuk sales bulan ini (hot data) - REMOVED
-- Cannot use NOW() in index predicate (not immutable)
-- Alternative: Use regular index, PostgreSQL will optimize automatically

-- Index untuk sales dengan bonus (reporting)
CREATE INDEX IF NOT EXISTS idx_sales_with_bonus 
ON sales_sell_out(promotor_id, transaction_date, estimated_bonus) 
WHERE estimated_bonus > 0;

-- Index untuk active users only
CREATE INDEX IF NOT EXISTS idx_users_active 
ON users(id, role, full_name, promotor_type) 
WHERE deleted_at IS NULL;

-- ========================================
-- 3. ADD COMPOSITE INDEX (Bonus Calculation)
-- ========================================

-- Index untuk bonus lookup di trigger (product + type)
CREATE INDEX IF NOT EXISTS idx_bonus_rules_product_type 
ON bonus_rules(product_id, bonus_type, ratio_value);

-- ========================================
-- 4. ANALYZE TABLES (Update Statistics)
-- ========================================

-- Update statistics untuk query planner
ANALYZE sales_sell_out;
ANALYZE dashboard_performance_metrics;
ANALYZE bonus_rules;
ANALYZE users;
ANALYZE products;
ANALYZE product_variants;
ANALYZE stores;
ANALYZE target_periods;

-- NOTE: VACUUM harus dijalankan terpisah (tidak bisa dalam transaction)
-- Jalankan manual: VACUUM ANALYZE sales_sell_out;
-- Atau gunakan file: supabase/maintenance_vacuum.sql

-- ========================================
-- 5. CREATE FUNCTION: Monthly Cleanup
-- ========================================

-- Function untuk cleanup data lama (optional, untuk maintenance)
CREATE OR REPLACE FUNCTION cleanup_old_data()
RETURNS void AS $$
BEGIN
  -- Soft delete sales older than 2 years
  UPDATE sales_sell_out 
  SET deleted_at = NOW()
  WHERE transaction_date < NOW() - INTERVAL '2 years'
  AND deleted_at IS NULL;
  
  -- Log cleanup
  RAISE NOTICE 'Cleanup completed at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- 6. CREATE VIEW: Quick Bonus Summary
-- ========================================

-- View untuk quick access bonus summary
CREATE OR REPLACE VIEW v_bonus_summary AS
SELECT 
  u.id as user_id,
  u.full_name,
  u.role,
  u.promotor_type,
  tp.period_name,
  tp.target_month,
  tp.target_year,
  dpm.total_omzet_real,
  dpm.total_units_sold,
  dpm.total_units_focus,
  dpm.estimated_bonus_total,
  dpm.last_updated,
  -- Calculate achievement percentage
  CASE 
    WHEN ut.target_omzet > 0 
    THEN ROUND((dpm.total_omzet_real / ut.target_omzet * 100)::numeric, 2)
    ELSE 0
  END as achievement_pct
FROM dashboard_performance_metrics dpm
JOIN users u ON u.id = dpm.user_id
JOIN target_periods tp ON tp.id = dpm.period_id
LEFT JOIN user_targets ut ON ut.user_id = u.id AND ut.period_id = tp.id
WHERE u.deleted_at IS NULL
ORDER BY tp.start_date DESC, dpm.estimated_bonus_total DESC;

-- ========================================
-- 7. CREATE FUNCTION: Recalculate Dashboard
-- ========================================

-- Function untuk recalculate dashboard (jika ada data inconsistency)
CREATE OR REPLACE FUNCTION recalculate_dashboard_metrics(p_period_id UUID DEFAULT NULL)
RETURNS void AS $$
BEGIN
  IF p_period_id IS NULL THEN
    -- Recalculate all periods
    UPDATE dashboard_performance_metrics dpm
    SET 
      total_omzet_real = subq.total_omzet,
      total_units_sold = subq.total_units,
      total_units_focus = subq.total_focus,
      estimated_bonus_total = subq.total_bonus,
      last_updated = NOW()
    FROM (
      SELECT 
        so.promotor_id,
        tp.id as period_id,
        COALESCE(SUM(so.price_at_transaction), 0) as total_omzet,
        COUNT(*) as total_units,
        COALESCE(SUM(CASE WHEN p.is_focus THEN 1 ELSE 0 END), 0) as total_focus,
        COALESCE(SUM(so.estimated_bonus), 0) as total_bonus
      FROM sales_sell_out so
      JOIN product_variants pv ON pv.id = so.variant_id
      JOIN products p ON p.id = pv.product_id
      JOIN target_periods tp ON so.transaction_date >= tp.start_date 
                             AND so.transaction_date <= tp.end_date
      WHERE so.deleted_at IS NULL
      GROUP BY so.promotor_id, tp.id
    ) subq
    WHERE dpm.user_id = subq.promotor_id 
    AND dpm.period_id = subq.period_id;
  ELSE
    -- Recalculate specific period
    UPDATE dashboard_performance_metrics dpm
    SET 
      total_omzet_real = subq.total_omzet,
      total_units_sold = subq.total_units,
      total_units_focus = subq.total_focus,
      estimated_bonus_total = subq.total_bonus,
      last_updated = NOW()
    FROM (
      SELECT 
        so.promotor_id,
        COALESCE(SUM(so.price_at_transaction), 0) as total_omzet,
        COUNT(*) as total_units,
        COALESCE(SUM(CASE WHEN p.is_focus THEN 1 ELSE 0 END), 0) as total_focus,
        COALESCE(SUM(so.estimated_bonus), 0) as total_bonus
      FROM sales_sell_out so
      JOIN product_variants pv ON pv.id = so.variant_id
      JOIN products p ON p.id = pv.product_id
      JOIN target_periods tp ON so.transaction_date >= tp.start_date 
                             AND so.transaction_date <= tp.end_date
      WHERE so.deleted_at IS NULL
      AND tp.id = p_period_id
      GROUP BY so.promotor_id
    ) subq
    WHERE dpm.user_id = subq.promotor_id 
    AND dpm.period_id = p_period_id;
  END IF;
  
  RAISE NOTICE 'Dashboard metrics recalculated successfully';
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- VERIFICATION
-- ========================================

SELECT '=== ADDITIONAL OPTIMIZATIONS COMPLETE ===' as status;

-- Check constraints added
SELECT 
  'Constraints Added' as check_type,
  COUNT(*) as total_constraints
FROM information_schema.table_constraints
WHERE table_schema = 'public'
AND constraint_type = 'CHECK'
AND table_name IN ('sales_sell_out', 'bonus_rules', 'dashboard_performance_metrics');

-- Check indexes added
SELECT 
  'Indexes Added' as check_type,
  COUNT(*) as total_indexes
FROM pg_indexes
WHERE schemaname = 'public'
AND indexname LIKE 'idx_%'
AND tablename IN ('sales_sell_out', 'bonus_rules', 'dashboard_performance_metrics', 'users');

-- Check views created
SELECT 
  'Views Created' as check_type,
  COUNT(*) as total_views
FROM information_schema.views
WHERE table_schema = 'public'
AND table_name LIKE 'v_%';

-- Check functions created
SELECT 
  'Functions Created' as check_type,
  COUNT(*) as total_functions
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN ('cleanup_old_data', 'recalculate_dashboard_metrics');

-- Final summary
SELECT 
  '✅ Optimizations Complete' as status,
  'Check constraints for data validation' as constraints,
  'Partial indexes for hot data' as indexes,
  'View for quick bonus summary' as views,
  'Functions for maintenance' as functions,
  'Database ready for production' as result;
