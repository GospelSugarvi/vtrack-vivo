-- Quick verification script to check admin connectivity
-- Run this to see which admin features are properly connected

-- ==========================================
-- 1. BONUS SYSTEM
-- ==========================================
SELECT '=== BONUS SYSTEM ===' as section;

SELECT 
    'bonus_rules' as table_name,
    COUNT(*) as total_rules,
    COUNT(*) FILTER (WHERE bonus_type = 'range') as range_rules,
    COUNT(*) FILTER (WHERE bonus_type = 'flat') as flat_rules,
    COUNT(*) FILTER (WHERE bonus_type = 'ratio') as ratio_rules
FROM bonus_rules;

-- Check if trigger uses bonus_rules
SELECT 
    'Trigger Check' as check_type,
    routine_name,
    CASE 
        WHEN routine_definition LIKE '%bonus_rules%' THEN '✅ Uses bonus_rules'
        ELSE '❌ Hardcoded'
    END as status
FROM information_schema.routines
WHERE routine_name = 'process_sell_out_insert';

-- ==========================================
-- 2. TARGET SYSTEM
-- ==========================================
SELECT '=== TARGET SYSTEM ===' as section;

SELECT 
    'target_periods' as table_name,
    COUNT(*) as total_periods
FROM target_periods
WHERE deleted_at IS NULL;

SELECT 
    'user_targets' as table_name,
    COUNT(*) as total_targets,
    COUNT(DISTINCT user_id) as users_with_targets,
    COUNT(DISTINCT period_id) as periods_with_targets
FROM user_targets;

-- Check if targets are used in calculations
SELECT 
    'Target Usage Check' as check_type,
    COUNT(*) as functions_using_targets
FROM information_schema.routines
WHERE routine_definition LIKE '%user_targets%'
OR routine_definition LIKE '%target_periods%';

-- ==========================================
-- 3. PRODUCT SYSTEM
-- ==========================================
SELECT '=== PRODUCT SYSTEM ===' as section;

SELECT 
    'products' as table_name,
    COUNT(*) as total_products,
    COUNT(*) FILTER (WHERE is_focus = true) as focus_products,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) as active_products
FROM products;

SELECT 
    'product_variants' as table_name,
    COUNT(*) as total_variants,
    COUNT(DISTINCT product_id) as products_with_variants
FROM product_variants
WHERE deleted_at IS NULL;

-- Check if products are used in sales
SELECT 
    'Product Usage in Sales' as check_type,
    COUNT(DISTINCT pv.product_id) as products_sold,
    COUNT(*) as total_sales
FROM sales_sell_out so
JOIN product_variants pv ON so.variant_id = pv.id;

-- ==========================================
-- 4. USER SYSTEM
-- ==========================================
SELECT '=== USER SYSTEM ===' as section;

SELECT 
    'users' as table_name,
    COUNT(*) as total_users,
    COUNT(*) FILTER (WHERE role = 'promotor') as promotors,
    COUNT(*) FILTER (WHERE role = 'sator') as sators,
    COUNT(*) FILTER (WHERE role = 'spv') as spvs,
    COUNT(*) FILTER (WHERE role = 'admin') as admins,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) as active_users
FROM users;

-- Check promotor type distribution
SELECT 
    'Promotor Types' as check_type,
    promotor_type,
    COUNT(*) as count
FROM users
WHERE role = 'promotor'
AND deleted_at IS NULL
GROUP BY promotor_type;

-- ==========================================
-- 5. STORE SYSTEM
-- ==========================================
SELECT '=== STORE SYSTEM ===' as section;

SELECT 
    'stores' as table_name,
    COUNT(*) as total_stores,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) as active_stores,
    COUNT(DISTINCT area) as areas
FROM stores;

-- Check store assignments
SELECT 
    'Store Assignments' as check_type,
    COUNT(*) as total_assignments,
    COUNT(DISTINCT promotor_id) as promotors_assigned,
    COUNT(DISTINCT store_id) as stores_with_promotors
FROM assignments_promotor_store
WHERE active = true;

-- ==========================================
-- 6. SATOR/SPV REWARD SYSTEM
-- ==========================================
SELECT '=== SATOR/SPV REWARDS ===' as section;

SELECT 
    'kpi_settings' as table_name,
    role,
    COUNT(*) as kpi_count,
    SUM(weight) as total_weight
FROM kpi_settings
GROUP BY role;

SELECT 
    'point_ranges' as table_name,
    role,
    COUNT(*) as range_count
FROM point_ranges
GROUP BY role;

SELECT 
    'special_rewards' as table_name,
    role,
    COUNT(*) as reward_count
FROM special_rewards
GROUP BY role;

-- ==========================================
-- 7. WEEKLY TARGET SYSTEM
-- ==========================================
SELECT '=== WEEKLY TARGETS ===' as section;

SELECT 
    'weekly_targets' as table_name,
    COUNT(*) as total_weeks,
    SUM(percentage) as total_percentage
FROM weekly_targets;

-- ==========================================
-- 8. FOKUS PRODUCT SYSTEM
-- ==========================================
SELECT '=== FOKUS PRODUCTS ===' as section;

SELECT 
    'fokus_bundles' as table_name,
    COUNT(*) as total_bundles,
    COUNT(DISTINCT period_id) as periods_with_bundles
FROM fokus_bundles;

SELECT 
    'fokus_targets' as table_name,
    COUNT(*) as total_targets,
    COUNT(DISTINCT user_id) as users_with_fokus_targets
FROM fokus_targets;

-- ==========================================
-- 9. MIN STOCK SYSTEM
-- ==========================================
SELECT '=== MIN STOCK SETTINGS ===' as section;

SELECT 
    'min_stock_settings' as table_name,
    COUNT(*) as total_settings,
    COUNT(DISTINCT store_id) as stores_with_settings,
    COUNT(DISTINCT variant_id) as variants_with_settings
FROM min_stock_settings;

-- ==========================================
-- 10. SHIFT SETTINGS
-- ==========================================
SELECT '=== SHIFT SETTINGS ===' as section;

SELECT 
    'shift_settings' as table_name,
    COUNT(*) as total_shifts
FROM shift_settings;

-- ==========================================
-- 11. ANNOUNCEMENTS
-- ==========================================
SELECT '=== ANNOUNCEMENTS ===' as section;

SELECT 
    'announcements' as table_name,
    COUNT(*) as total_announcements,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) as active_announcements
FROM announcements;

-- ==========================================
-- SUMMARY
-- ==========================================
SELECT '=== CONNECTIVITY SUMMARY ===' as section;

SELECT 
    'Admin Tables' as metric,
    COUNT(DISTINCT table_name) as count
FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN (
    'bonus_rules', 'target_periods', 'user_targets', 'products', 'product_variants',
    'users', 'stores', 'kpi_settings', 'point_ranges', 'special_rewards',
    'weekly_targets', 'fokus_bundles', 'fokus_targets', 'min_stock_settings',
    'shift_settings', 'announcements'
);

SELECT 
    'Functions/Triggers' as metric,
    COUNT(*) as count
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_type IN ('FUNCTION', 'TRIGGER');
