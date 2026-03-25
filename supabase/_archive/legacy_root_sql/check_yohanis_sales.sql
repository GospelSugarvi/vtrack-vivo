-- Check if Yohanis has any sales data
-- ==========================================

-- 1. Check sales_sell_out
SELECT 
    '=== SALES DATA ===' as check,
    COUNT(*) as total_sales,
    SUM(price_at_transaction) as total_omzet,
    MIN(transaction_date) as first_sale,
    MAX(transaction_date) as last_sale
FROM sales_sell_out
WHERE promotor_id = 'a85b7470-47f8-481c-9dd0-d77ad851b4a7'
AND deleted_at IS NULL;

-- 2. Check dashboard_performance_metrics
SELECT 
    '=== DASHBOARD METRICS ===' as check,
    user_id,
    period_id,
    total_omzet_real,
    total_units_focus,
    last_updated
FROM dashboard_performance_metrics
WHERE user_id = 'a85b7470-47f8-481c-9dd0-d77ad851b4a7';

-- 3. Check if dashboard_performance_metrics table exists
SELECT 
    '=== TABLE CHECK ===' as check,
    EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'dashboard_performance_metrics'
    ) as table_exists;

-- 4. If no metrics, check what period Yohanis has target for
SELECT 
    '=== TARGET PERIOD ===' as check,
    tp.id as period_id,
    tp.period_name,
    tp.start_date,
    tp.end_date,
    ut.target_omzet,
    ut.target_fokus_total
FROM user_targets ut
JOIN target_periods tp ON ut.period_id = tp.id
WHERE ut.user_id = 'a85b7470-47f8-481c-9dd0-d77ad851b4a7';

-- 5. Check sales within target period
SELECT 
    '=== SALES IN PERIOD ===' as check,
    COUNT(*) as sales_count,
    SUM(so.price_at_transaction) as total_omzet,
    COUNT(CASE WHEN p.is_fokus = true THEN 1 END) as fokus_count
FROM sales_sell_out so
JOIN product_variants pv ON so.variant_id = pv.id
JOIN products p ON pv.product_id = p.id
WHERE so.promotor_id = 'a85b7470-47f8-481c-9dd0-d77ad851b4a7'
AND so.transaction_date >= '2026-01-01'
AND so.transaction_date <= '2026-01-31'
AND so.deleted_at IS NULL;
