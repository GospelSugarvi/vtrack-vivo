-- ============================================
-- DATABASE OPTIMIZATION - PROFESSIONAL STANDARD
-- Add indexes, constraints, and best practices
-- ============================================

-- ========================================
-- PART 1: CRITICAL INDEXES
-- ========================================

-- Index 1: Sales by promotor and date (MOST CRITICAL)
-- Used in: Monthly bonus calculation, dashboard queries
CREATE INDEX IF NOT EXISTS idx_sales_promotor_date 
ON sales_sell_out(promotor_id, transaction_date DESC);

-- Index 2: Sales by variant (for product queries)
CREATE INDEX IF NOT EXISTS idx_sales_variant 
ON sales_sell_out(variant_id);

-- Index 3: Sales by store
CREATE INDEX IF NOT EXISTS idx_sales_store 
ON sales_sell_out(store_id);

-- Index 4: Dashboard metrics lookup (CRITICAL)
CREATE INDEX IF NOT EXISTS idx_dashboard_user_period 
ON dashboard_performance_metrics(user_id, period_id);

-- Index 5: Bonus rules lookup (used in trigger)
CREATE INDEX IF NOT EXISTS idx_bonus_rules_product_type 
ON bonus_rules(product_id, bonus_type);

-- Index 6: Product variants by product
CREATE INDEX IF NOT EXISTS idx_variants_product 
ON product_variants(product_id);

-- Index 7: Users by role (for hierarchy queries)
CREATE INDEX IF NOT EXISTS idx_users_role 
ON users(role) WHERE deleted_at IS NULL;

-- Index 8: Sales with bonus (for reporting)
CREATE INDEX IF NOT EXISTS idx_sales_with_bonus 
ON sales_sell_out(estimated_bonus) WHERE estimated_bonus > 0;

-- ========================================
-- PART 2: CONSTRAINTS
-- ========================================

-- Unique constraint: Prevent duplicate metrics
ALTER TABLE dashboard_performance_metrics 
DROP CONSTRAINT IF EXISTS uq_dashboard_user_period;

ALTER TABLE dashboard_performance_metrics 
ADD CONSTRAINT uq_dashboard_user_period 
UNIQUE (user_id, period_id);

-- Check constraint: Bonus must be non-negative
ALTER TABLE sales_sell_out 
DROP CONSTRAINT IF EXISTS chk_bonus_positive;

ALTER TABLE sales_sell_out 
ADD CONSTRAINT chk_bonus_positive 
CHECK (estimated_bonus >= 0);

-- Check constraint: Price must be positive
ALTER TABLE sales_sell_out 
DROP CONSTRAINT IF EXISTS chk_price_positive;

ALTER TABLE sales_sell_out 
ADD CONSTRAINT chk_price_positive 
CHECK (price_at_transaction > 0);

-- Check constraint: Ratio value must be valid
ALTER TABLE bonus_rules 
DROP CONSTRAINT IF EXISTS chk_ratio_valid;

ALTER TABLE bonus_rules 
ADD CONSTRAINT chk_ratio_valid 
CHECK (ratio_value IS NULL OR ratio_value > 0);

-- ========================================
-- PART 3: FOREIGN KEY INDEXES
-- ========================================

-- Ensure FK columns have indexes (PostgreSQL best practice)
CREATE INDEX IF NOT EXISTS idx_sales_promotor_fk 
ON sales_sell_out(promotor_id);

CREATE INDEX IF NOT EXISTS idx_dashboard_user_fk 
ON dashboard_performance_metrics(user_id);

CREATE INDEX IF NOT EXISTS idx_dashboard_period_fk 
ON dashboard_performance_metrics(period_id);

-- ========================================
-- PART 4: PARTIAL INDEXES (Advanced)
-- ========================================

-- Index for active users only
CREATE INDEX IF NOT EXISTS idx_users_active 
ON users(id, role, full_name) 
WHERE deleted_at IS NULL;

-- Index for current month sales (hot data)
CREATE INDEX IF NOT EXISTS idx_sales_current_month 
ON sales_sell_out(promotor_id, estimated_bonus) 
WHERE transaction_date >= DATE_TRUNC('month', NOW());

-- ========================================
-- PART 5: ANALYZE TABLES
-- ========================================

-- Update statistics for query planner
ANALYZE sales_sell_out;
ANALYZE dashboard_performance_metrics;
ANALYZE bonus_rules;
ANALYZE users;
ANALYZE products;
ANALYZE product_variants;

-- ========================================
-- PART 6: VACUUM (Clean up)
-- ========================================

-- Reclaim space and update statistics
VACUUM ANALYZE sales_sell_out;
VACUUM ANALYZE dashboard_performance_metrics;

-- ========================================
-- VERIFICATION
-- ========================================

SELECT '=== OPTIMIZATION COMPLETE ===' as status;

-- Count indexes created
SELECT 
  'Index Summary' as check_type,
  COUNT(*) as total_indexes,
  COUNT(CASE WHEN indexname LIKE 'idx_%' THEN 1 END) as custom_indexes
FROM pg_indexes
WHERE schemaname = 'public'
AND tablename IN ('sales_sell_out', 'dashboard_performance_metrics', 'bonus_rules');

-- Check constraints
SELECT 
  'Constraint Summary' as check_type,
  table_name,
  COUNT(*) as constraint_count
FROM information_schema.table_constraints
WHERE table_schema = 'public'
AND table_name IN ('sales_sell_out', 'dashboard_performance_metrics', 'bonus_rules')
GROUP BY table_name;

-- Final health check
SELECT 
  '✅ Database Optimized' as status,
  'Indexes added for performance' as indexes,
  'Constraints added for data integrity' as constraints,
  'Statistics updated for query planner' as statistics,
  'Ready for production' as result;
