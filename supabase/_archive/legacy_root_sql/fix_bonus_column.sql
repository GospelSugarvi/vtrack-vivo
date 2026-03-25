-- Fix column name error in get_promotor_bonus_details function
-- Run this directly on your Supabase SQL Editor

CREATE OR REPLACE FUNCTION get_promotor_bonus_details(
    p_promotor_id UUID,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    transaction_id UUID,
    transaction_date DATE,
    product_name TEXT,
    variant_name TEXT,
    price NUMERIC,
    bonus_amount NUMERIC,
    payment_method TEXT,
    leasing_provider TEXT
) AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    -- Default to current month if dates not provided
    v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_end_date := COALESCE(p_end_date, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE);
    
    RETURN QUERY
    SELECT 
        so.id as transaction_id,
        so.transaction_date,
        (p.series || ' ' || p.model_name) as product_name,
        pv.ram_rom || ' ' || pv.color as variant_name,
        so.price_at_transaction as price,
        so.estimated_bonus as bonus_amount,
        so.payment_method,
        so.leasing_provider
    FROM sales_sell_out so
    JOIN product_variants pv ON pv.id = so.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE so.promotor_id = p_promotor_id
    AND so.transaction_date BETWEEN v_start_date AND v_end_date
    ORDER BY so.transaction_date DESC, so.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
