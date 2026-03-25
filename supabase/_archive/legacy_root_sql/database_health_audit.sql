-- ============================================
-- DATABASE HEALTH AUDIT
-- Cek index, aggregate, constraints, performance
-- ============================================

-- 1. CEK INDEX YANG ADA
SELECT '=== 1. EXISTING INDEXES ===' as section;
SELECT 
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
AND tablename IN (
  'sales_sell_out',
  'dashboard_performance_metrics',
  'bonus_rules',
  'users',
  'products',
  'product_variants',
  'stores',
  'target_periods'
)
ORDER BY tablename, indexname;

-- 2. CEK MISSING INDEXES (Query yang sering dipakai)
SELECT '=== 2. RECOMMENDED INDEXES ===' as section;
SELECT 
  'Missing Index Check' as check_type,
  'sales_sell_out(promotor_id, transaction_date)' as recommended_index,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_indexes 
      WHERE tablename = 'sales_sell_out' 
      AND indexdef LIKE '%promotor_id%transaction_date%'
    ) THEN '✅ Exists'
    ELSE '❌ Missing - CRITICAL for performance'
  END as status
UNION ALL
SELECT 
  'Missing Index Check',
  'sales_sell_out(variant_id)',
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_indexes 
      WHERE tablename = 'sales_sell_out' 
      AND indexdef LIKE '%variant_id%'
    ) THEN '✅ Exists'
    ELSE '❌ Missing'
  END
UNION ALL
SELECT 
  'Missing Index Check',
  'dashboard_performance_metrics(user_id, period_id)',
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_indexes 
      WHERE tablename = 'dashboard_performance_metrics' 
      AND indexdef LIKE '%user_id%period_id%'
    ) THEN '✅ Exists'
    ELSE '❌ Missing - CRITICAL for dashboard'
  END
UNION ALL
SELECT 
  'Missing Index Check',
  'bonus_rules(product_id, bonus_type)',
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM pg_indexes 
      WHERE tablename = 'bonus_rules' 
      AND indexdef LIKE '%product_id%'
    ) THEN '✅ Exists'
    ELSE '❌ Missing'
  END;

-- 3. CEK CONSTRAINTS (Foreign Keys, Unique, Check)
SELECT '=== 3. CONSTRAINTS ===' as section;
SELECT 
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
LEFT JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.table_schema = 'public'
AND tc.table_name IN (
  'sales_sell_out',
  'dashboard_performance_metrics',
  'bonus_rules'
)
ORDER BY tc.table_name, tc.constraint_type;

-- 4. CEK TABLE SIZE & ROW COUNT
SELECT '=== 4. TABLE STATISTICS ===' as section;
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size,
  (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.tablename) as column_count
FROM pg_tables t
WHERE schemaname = 'public'
AND tablename IN (
  'sales_sell_out',
  'dashboard_performance_metrics',
  'bonus_rules',
  'users',
  'products',
  'stores'
)
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- 5. CEK AGGREGATE TABLES
SELECT '=== 5. AGGREGATE TABLES ===' as section;
SELECT 
  'Aggregate Check' as check_type,
  CASE 
    WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dashboard_performance_metrics')
    THEN '✅ dashboard_performance_metrics exists'
    ELSE '❌ Missing aggregate table'
  END as dashboard_metrics,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'dashboard_performance_metrics' 
      AND column_name = 'estimated_bonus_total'
    )
    THEN '✅ Bonus column exists'
    ELSE '❌ Bonus column missing'
  END as bonus_column,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'dashboard_performance_metrics' 
      AND column_name = 'total_omzet_real'
    )
    THEN '✅ Omzet column exists'
    ELSE '❌ Omzet column missing'
  END as omzet_column;

-- 6. CEK TRIGGER UNTUK AUTO-AGGREGATE
SELECT '=== 6. TRIGGERS ===' as section;
SELECT 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table IN ('sales_sell_out', 'dashboard_performance_metrics')
ORDER BY event_object_table, trigger_name;

-- 7. CEK SLOW QUERIES (Simulasi)
SELECT '=== 7. QUERY PERFORMANCE TEST ===' as section;

-- Test 1: Get promotor bonus (should be fast with aggregate)
EXPLAIN ANALYZE
SELECT 
  u.full_name,
  dpm.estimated_bonus_total
FROM dashboard_performance_metrics dpm
JOIN users u ON u.id = dpm.user_id
WHERE dpm.period_id = (SELECT id FROM target_periods ORDER BY start_date DESC LIMIT 1)
LIMIT 10;

-- 8. CEK DATA INTEGRITY
SELECT '=== 8. DATA INTEGRITY ===' as section;
SELECT 
  'Integrity Check' as check_type,
  (SELECT COUNT(*) FROM sales_sell_out WHERE promotor_id IS NULL) as sales_without_promotor,
  (SELECT COUNT(*) FROM sales_sell_out WHERE variant_id IS NULL) as sales_without_variant,
  (SELECT COUNT(*) FROM sales_sell_out WHERE store_id IS NULL) as sales_without_store,
  (SELECT COUNT(*) FROM dashboard_performance_metrics WHERE user_id IS NULL) as metrics_without_user,
  (SELECT COUNT(*) FROM dashboard_performance_metrics WHERE period_id IS NULL) as metrics_without_period;

-- 9. CEK ORPHANED RECORDS
SELECT '=== 9. ORPHANED RECORDS ===' as section;
SELECT 
  'Orphaned Check' as check_type,
  (SELECT COUNT(*) 
   FROM sales_sell_out so 
   WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = so.promotor_id)
  ) as sales_with_invalid_promotor,
  (SELECT COUNT(*) 
   FROM sales_sell_out so 
   WHERE NOT EXISTS (SELECT 1 FROM product_variants pv WHERE pv.id = so.variant_id)
  ) as sales_with_invalid_variant,
  (SELECT COUNT(*) 
   FROM dashboard_performance_metrics dpm 
   WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = dpm.user_id)
  ) as metrics_with_invalid_user;

-- 10. RECOMMENDATIONS SUMMARY
SELECT '=== 10. RECOMMENDATIONS ===' as section;
SELECT 
  'Recommendation' as type,
  'Add composite index on sales_sell_out(promotor_id, transaction_date)' as action,
  'CRITICAL' as priority,
  'Speeds up monthly bonus calculation' as reason
UNION ALL
SELECT 
  'Recommendation',
  'Add index on sales_sell_out(variant_id)',
  'HIGH',
  'Speeds up product-based queries'
UNION ALL
SELECT 
  'Recommendation',
  'Add unique constraint on dashboard_performance_metrics(user_id, period_id)',
  'HIGH',
  'Prevents duplicate metrics'
UNION ALL
SELECT 
  'Recommendation',
  'Add index on bonus_rules(product_id, bonus_type)',
  'MEDIUM',
  'Speeds up bonus lookup in trigger'
UNION ALL
SELECT 
  'Recommendation',
  'Consider partitioning sales_sell_out by transaction_date',
  'LOW',
  'For future scalability when data > 1M rows';
