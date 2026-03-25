-- AllBrand Helper Functions Only
-- Run this if table already exists but functions are missing

-- Function to get VIVO auto data for today
CREATE OR REPLACE FUNCTION get_vivo_auto_data(
    p_store_id UUID,
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'under_2m', COUNT(*) FILTER (WHERE so.price_at_transaction < 2000000),
        '2m_4m', COUNT(*) FILTER (WHERE so.price_at_transaction >= 2000000 AND so.price_at_transaction < 4000000),
        '4m_6m', COUNT(*) FILTER (WHERE so.price_at_transaction >= 4000000 AND so.price_at_transaction < 6000000),
        'above_6m', COUNT(*) FILTER (WHERE so.price_at_transaction >= 6000000),
        'total', COUNT(*)
    ) INTO v_result
    FROM sales_sell_out so
    WHERE so.store_id = p_store_id
    AND so.transaction_date = p_date;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if allbrand report exists today
CREATE OR REPLACE FUNCTION has_allbrand_report_today(
    p_promotor_id UUID,
    p_store_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM allbrand_reports
        WHERE promotor_id = p_promotor_id
        AND store_id = p_store_id
        AND report_date = CURRENT_DATE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get allbrand summary for a date range
CREATE OR REPLACE FUNCTION get_allbrand_summary(
    p_store_id UUID,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_summary JSON;
BEGIN
    -- Default to current month if dates not provided
    v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_end_date := COALESCE(p_end_date, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE);
    
    SELECT json_build_object(
        'total_reports', COUNT(*),
        'latest_report_date', MAX(report_date),
        'brands_tracked', (
            SELECT json_object_agg(brand_key, brand_totals)
            FROM (
                SELECT 
                    brand_key,
                    json_build_object(
                        'total_units', SUM((brand_value->>'under_2m')::int + 
                                          (brand_value->>'2m_4m')::int + 
                                          (brand_value->>'4m_6m')::int + 
                                          (brand_value->>'above_6m')::int),
                        'avg_promotors', AVG((brand_value->>'promotor_count')::int)
                    ) as brand_totals
                FROM allbrand_reports r
                CROSS JOIN LATERAL jsonb_each(
                    CASE
                        WHEN jsonb_typeof(r.brand_data) = 'object' THEN r.brand_data
                        ELSE '{}'::jsonb
                    END
                ) as brand_entry(brand_key, brand_value)
                WHERE r.store_id = p_store_id
                AND r.report_date BETWEEN v_start_date AND v_end_date
                GROUP BY brand_key
            ) brand_summary
        ),
        'period_start', v_start_date,
        'period_end', v_end_date
    ) INTO v_summary
    FROM allbrand_reports
    WHERE store_id = p_store_id
    AND report_date BETWEEN v_start_date AND v_end_date;
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_vivo_auto_data TO authenticated;
GRANT EXECUTE ON FUNCTION has_allbrand_report_today TO authenticated;
GRANT EXECUTE ON FUNCTION get_allbrand_summary TO authenticated;

-- Add comments
COMMENT ON FUNCTION get_vivo_auto_data IS 'Get VIVO sales data auto-calculated from system';
COMMENT ON FUNCTION has_allbrand_report_today IS 'Check if promotor has submitted allbrand report today';
COMMENT ON FUNCTION get_allbrand_summary IS 'Get allbrand summary for a store in a date range';
