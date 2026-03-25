-- Test query untuk debug get_live_feed
-- Run this to see what columns are actually returned

SELECT 
    so.id as feed_id,
    'sale'::TEXT as feed_type,
    so.id as sale_id,
    u.id as promotor_id,
    u.full_name as promotor_name,
    st.store_name,
    (p.series || ' ' || p.model_name) as product_name,
    (pv.ram_rom || ' ' || pv.color) as variant_name,
    so.price_at_transaction as price,
    so.estimated_bonus as bonus,
    so.payment_method,
    so.leasing_provider,
    so.customer_type,
    so.notes,
    so.image_proof_url as image_url,
    so.created_at
FROM sales_sell_out so
JOIN users u ON u.id = so.promotor_id
JOIN stores st ON st.id = so.store_id
JOIN product_variants pv ON pv.id = so.variant_id
JOIN products p ON p.id = pv.product_id
WHERE so.transaction_date = CURRENT_DATE
AND so.deleted_at IS NULL
LIMIT 5;
