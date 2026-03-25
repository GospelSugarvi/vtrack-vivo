-- Check sales data for ANTONIO's stores

-- 1. Check if there are any sales in the system
SELECT '1. Total sales in system:' as info;
SELECT 
    COUNT(*) as total_sales,
    MIN(transaction_date) as earliest_date,
    MAX(transaction_date) as latest_date
FROM sales_sell_out
WHERE deleted_at IS NULL;

-- 2. Check sales in ANTONIO's stores
SELECT '2. Sales in ANTONIO stores:' as info;
SELECT 
    s.store_name,
    COUNT(so.id) as total_sales,
    SUM(so.price_at_transaction) as total_revenue,
    MIN(so.transaction_date) as first_sale,
    MAX(so.transaction_date) as last_sale
FROM sales_sell_out so
JOIN stores s ON s.id = so.store_id
WHERE s.id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND so.deleted_at IS NULL
GROUP BY s.id, s.store_name
ORDER BY total_sales DESC;

-- 3. Check sales by promotor in ANTONIO's stores
SELECT '3. Sales by promotor in ANTONIO stores:' as info;
SELECT 
    u.full_name as promotor_name,
    s.store_name,
    COUNT(so.id) as total_sales,
    SUM(so.price_at_transaction) as total_revenue,
    so.transaction_date
FROM sales_sell_out so
JOIN users u ON u.id = so.promotor_id
JOIN stores s ON s.id = so.store_id
WHERE s.id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND so.deleted_at IS NULL
GROUP BY u.id, u.full_name, s.id, s.store_name, so.transaction_date
ORDER BY so.transaction_date DESC, s.store_name;

-- 4. Check today's sales for ANTONIO
SELECT '4. Today sales for ANTONIO:' as info;
SELECT 
    COUNT(*) as total_sales_today,
    SUM(price_at_transaction) as revenue_today
FROM sales_sell_out so
WHERE so.store_id IN (
    SELECT store_id 
    FROM assignments_sator_store 
    WHERE sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
    AND active = true
)
AND so.transaction_date = CURRENT_DATE
AND so.deleted_at IS NULL;

-- 5. Test get_sator_daily_summary function
SELECT '5. Test get_sator_daily_summary for today:' as info;
SELECT get_sator_daily_summary(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
    CURRENT_DATE
);

-- 6. Test get_sator_daily_summary for latest sale date
SELECT '6. Test get_sator_daily_summary for latest sale date:' as info;
SELECT get_sator_daily_summary(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
    (SELECT MAX(transaction_date) FROM sales_sell_out WHERE deleted_at IS NULL)
);

-- 7. Check if promotors are assigned to stores correctly
SELECT '7. Promotor assignments in ANTONIO stores:' as info;
SELECT 
    s.store_name,
    u.full_name as promotor_name,
    aps.active as assignment_active
FROM stores s
JOIN assignments_sator_store ass ON ass.store_id = s.id
JOIN assignments_promotor_store aps ON aps.store_id = s.id
JOIN users u ON u.id = aps.promotor_id
WHERE ass.sator_id = (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
AND ass.active = true
AND u.role = 'promotor'
ORDER BY s.store_name, u.full_name;
