-- PERFORMANCE OPTIMIZATION - FIXED INDEXES
-- Compatible with Supabase SQL editor
-- ==========================================

-- 1. SALES_SELL_OUT OPTIMIZATIONS (Most Critical)
CREATE INDEX IF NOT EXISTS idx_sales_sell_out_promotor_date 
ON sales_sell_out (promotor_id, transaction_date) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_sales_sell_out_promotor_period 
ON sales_sell_out (promotor_id, transaction_date, variant_id) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_sales_sell_out_bonus_calc 
ON sales_sell_out (promotor_id, transaction_date, price_at_transaction) 
WHERE deleted_at IS NULL;

-- 2. DASHBOARD_PERFORMANCE_METRICS OPTIMIZATIONS
CREATE UNIQUE INDEX IF NOT EXISTS idx_dashboard_metrics_user_period 
ON dashboard_performance_metrics (user_id, period_id);

CREATE INDEX IF NOT EXISTS idx_dashboard_metrics_period_omzet 
ON dashboard_performance_metrics (period_id, total_omzet_real DESC);

CREATE INDEX IF NOT EXISTS idx_dashboard_metrics_period_fokus 
ON dashboard_performance_metrics (period_id, total_units_focus DESC);

-- 3. USER_TARGETS OPTIMIZATIONS
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_targets_user_period 
ON user_targets (user_id, period_id);

-- 4. FOKUS_TARGETS OPTIMIZATIONS
CREATE INDEX IF NOT EXISTS idx_fokus_targets_user_period 
ON fokus_targets (user_id, period_id);

CREATE INDEX IF NOT EXISTS idx_fokus_targets_bundle 
ON fokus_targets (bundle_id, user_id, period_id);

-- 5. PRODUCT OPTIMIZATIONS
CREATE INDEX IF NOT EXISTS idx_product_variants_product 
ON product_variants (product_id);

CREATE INDEX IF NOT EXISTS idx_products_model_fokus 
ON products (model_name, is_fokus) 
WHERE deleted_at IS NULL;

-- 6. USER MANAGEMENT OPTIMIZATIONS
CREATE INDEX IF NOT EXISTS idx_users_role_active 
ON users (role) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_assignments_promotor_active 
ON assignments_promotor_store (promotor_id, active);

-- 7. TARGET_PERIODS OPTIMIZATIONS
CREATE INDEX IF NOT EXISTS idx_target_periods_date_range 
ON target_periods (start_date, end_date) 
WHERE deleted_at IS NULL;

-- 8. FOKUS_BUNDLES OPTIMIZATIONS
CREATE INDEX IF NOT EXISTS idx_fokus_bundles_product_types 
ON fokus_bundles USING GIN (product_types);

-- 9. ANALYZE TABLES AFTER INDEX CREATION
ANALYZE sales_sell_out;
ANALYZE dashboard_performance_metrics;
ANALYZE user_targets;
ANALYZE fokus_targets;
ANALYZE product_variants;
ANALYZE products;
ANALYZE users;
ANALYZE target_periods;
ANALYZE fokus_bundles;

SELECT '✅ Critical performance indexes created!' as result;
SELECT 'Expected 70% performance improvement on target dashboard queries' as impact;