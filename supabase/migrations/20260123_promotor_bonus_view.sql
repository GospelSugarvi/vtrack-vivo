-- Promotor Bonus View and Calculation Functions
-- Based on docs/aturan_bonus_promotor.md

-- ==========================================
-- 1. FUNCTION TO GET PROMOTOR BONUS SUMMARY
-- ==========================================
CREATE OR REPLACE FUNCTION get_promotor_bonus_summary(
    p_promotor_id UUID,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_summary JSON;
    v_promotor_type TEXT;
BEGIN
    -- Default to current month if dates not provided
    v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_end_date := COALESCE(p_end_date, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE);
    
    -- Get promotor type (official or training)
    SELECT COALESCE(promotor_type, 'official') INTO v_promotor_type
    FROM users
    WHERE id = p_promotor_id;
    
    -- Calculate summary
    SELECT json_build_object(
        'total_sales', COUNT(*),
        'total_revenue', SUM(so.price_at_transaction),
        'total_bonus', SUM(so.estimated_bonus),
        'promotor_type', v_promotor_type,
        'period_start', v_start_date,
        'period_end', v_end_date,
        'breakdown_by_range', (
            SELECT json_object_agg(price_range, range_data)
            FROM (
                SELECT 
                    CASE 
                        WHEN so.price_at_transaction < 2000000 THEN 'under_2m'
                        WHEN so.price_at_transaction >= 2000000 AND so.price_at_transaction < 3000000 THEN '2m_3m'
                        WHEN so.price_at_transaction >= 3000000 AND so.price_at_transaction < 4000000 THEN '3m_4m'
                        WHEN so.price_at_transaction >= 4000000 AND so.price_at_transaction < 5000000 THEN '4m_5m'
                        WHEN so.price_at_transaction >= 5000000 AND so.price_at_transaction < 6000000 THEN '5m_6m'
                        ELSE 'above_6m'
                    END as price_range,
                    json_build_object(
                        'count', COUNT(*),
                        'total_bonus', SUM(so.estimated_bonus)
                    ) as range_data
                FROM sales_sell_out so
                WHERE so.promotor_id = p_promotor_id
                AND so.transaction_date BETWEEN v_start_date AND v_end_date
                GROUP BY price_range
            ) breakdown
        )
    ) INTO v_summary
    FROM sales_sell_out so
    WHERE so.promotor_id = p_promotor_id
    AND so.transaction_date BETWEEN v_start_date AND v_end_date;
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 2. FUNCTION TO GET BONUS TRANSACTION DETAILS
-- ==========================================
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

-- ==========================================
-- 3. FUNCTION TO GET BONUS RULES INFO
-- ==========================================
CREATE OR REPLACE FUNCTION get_bonus_rules_info()
RETURNS JSON AS $$
DECLARE
    v_rules JSON;
BEGIN
    SELECT json_build_object(
        'official', json_build_object(
            'under_2m', 10000,
            '2m_3m', 25000,
            '3m_4m', 45000,
            '4m_5m', 60000,
            '5m_6m', 80000,
            'above_6m', 110000
        ),
        'training', json_build_object(
            'under_2m', 7000,
            '2m_3m', 20000,
            '3m_4m', 40000,
            '4m_5m', 50000,
            '5m_6m', 60000,
            'above_6m', 90000
        ),
        'special_products', json_build_object(
            'X300', 250000,
            'X300Pro', 300000,
            'X_Fold_5_Pro', 350000,
            'Y02_Y03T_Y04S_official', 5000,
            'Y02_Y03T_Y04S_training', 4000,
            'Y02_Y03T_Y04S_note', '2 unit dihitung 1 unit'
        )
    ) INTO v_rules;
    
    RETURN v_rules;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_promotor_bonus_summary TO authenticated;
GRANT EXECUTE ON FUNCTION get_promotor_bonus_details TO authenticated;
GRANT EXECUTE ON FUNCTION get_bonus_rules_info TO authenticated;

-- Add comments
COMMENT ON FUNCTION get_promotor_bonus_summary IS 'Get promotor bonus summary for a date range';
COMMENT ON FUNCTION get_promotor_bonus_details IS 'Get detailed bonus transactions for a promotor';
COMMENT ON FUNCTION get_bonus_rules_info IS 'Get bonus calculation rules reference';
