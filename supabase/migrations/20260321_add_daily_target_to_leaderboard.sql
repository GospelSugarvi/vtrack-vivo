DROP FUNCTION IF EXISTS public.get_daily_ranking(DATE, UUID, INTEGER);

CREATE FUNCTION public.get_daily_ranking(
    p_date DATE DEFAULT CURRENT_DATE,
    p_area_id UUID DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
    rank INTEGER,
    promotor_id UUID,
    promotor_name TEXT,
    store_name TEXT,
    total_sales INTEGER,
    total_bonus NUMERIC,
    daily_target NUMERIC,
    has_sold BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH sale_bonus AS (
        SELECT
            so.id AS sales_sell_out_id,
            CASE
                WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC
                WHEN COALESCE(so.estimated_bonus, 0) > 0 THEN COALESCE(so.estimated_bonus, 0)::NUMERIC
                ELSE 0::NUMERIC
            END AS total_bonus
        FROM public.sales_sell_out so
        LEFT JOIN public.sales_bonus_events sbe
          ON sbe.sales_sell_out_id = so.id
        GROUP BY so.id, so.estimated_bonus
    ),
    daily_sales AS (
        SELECT
            so.promotor_id,
            COUNT(*)::INTEGER AS sales_count,
            COALESCE(SUM(sb.total_bonus), 0)::NUMERIC AS bonus_total
        FROM public.sales_sell_out so
        LEFT JOIN sale_bonus sb ON sb.sales_sell_out_id = so.id
        WHERE so.transaction_date = p_date
          AND so.deleted_at IS NULL
          AND COALESCE(so.is_chip_sale, false) = false
        GROUP BY so.promotor_id
    ),
    all_promotors AS (
        SELECT
            u.id AS promotor_id,
            u.full_name AS promotor_name,
            s.store_name,
            COALESCE(ds.sales_count, 0)::INTEGER AS total_sales,
            COALESCE(ds.bonus_total, 0)::NUMERIC AS total_bonus,
            COALESCE(dtd.target_daily_all_type, 0)::NUMERIC AS daily_target,
            (ds.sales_count IS NOT NULL) AS has_sold
        FROM public.users u
        JOIN public.assignments_promotor_store aps
          ON aps.promotor_id = u.id
         AND aps.active = true
        JOIN public.stores s
          ON s.id = aps.store_id
        LEFT JOIN daily_sales ds
          ON ds.promotor_id = u.id
        LEFT JOIN LATERAL public.get_daily_target_dashboard(u.id, p_date) dtd
          ON TRUE
        WHERE u.role = 'promotor'
          AND u.deleted_at IS NULL
    )
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY ap.total_bonus DESC, ap.total_sales DESC, ap.promotor_name
        )::INTEGER AS rank,
        ap.promotor_id,
        ap.promotor_name,
        ap.store_name,
        ap.total_sales,
        ap.total_bonus,
        ap.daily_target,
        ap.has_sold
    FROM all_promotors ap
    ORDER BY ap.total_bonus DESC, ap.total_sales DESC, ap.promotor_name
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_daily_ranking(DATE, UUID, INTEGER) TO authenticated;
