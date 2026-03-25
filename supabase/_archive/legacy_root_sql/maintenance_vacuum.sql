-- ============================================
-- MAINTENANCE: VACUUM
-- Reclaim space and update statistics
-- NOTE: Jalankan file ini TERPISAH (tidak dalam transaction)
-- ============================================

-- Vacuum tables untuk reclaim space
VACUUM ANALYZE sales_sell_out;
VACUUM ANALYZE dashboard_performance_metrics;
VACUUM ANALYZE bonus_rules;
VACUUM ANALYZE users;
VACUUM ANALYZE products;
VACUUM ANALYZE product_variants;
VACUUM ANALYZE stores;

-- Check hasil
SELECT 
  '✅ VACUUM Complete' as status,
  'Space reclaimed and statistics updated' as result;
