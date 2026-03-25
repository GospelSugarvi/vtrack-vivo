-- Fix jsonb_each failures when historical brand_data is not a JSON object.

UPDATE public.allbrand_reports
SET brand_data = '{}'::jsonb
WHERE brand_data IS NULL
   OR jsonb_typeof(brand_data) <> 'object';

UPDATE public.allbrand_reports
SET brand_data_daily = '{}'::jsonb
WHERE brand_data_daily IS NULL
   OR jsonb_typeof(brand_data_daily) <> 'object';

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
                        'total_units', SUM(
                            COALESCE((brand_value->>'under_2m')::int, 0) +
                            COALESCE((brand_value->>'2m_4m')::int, 0) +
                            COALESCE((brand_value->>'4m_6m')::int, 0) +
                            COALESCE((brand_value->>'above_6m')::int, 0)
                        ),
                        'avg_promotors', AVG(COALESCE((brand_value->>'promotor_count')::int, 0))
                    ) AS brand_totals
                FROM allbrand_reports r
                CROSS JOIN LATERAL jsonb_each(
                    CASE
                        WHEN jsonb_typeof(r.brand_data) = 'object' THEN r.brand_data
                        ELSE '{}'::jsonb
                    END
                ) AS brand_entry(brand_key, brand_value)
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

GRANT EXECUTE ON FUNCTION get_allbrand_summary TO authenticated;
