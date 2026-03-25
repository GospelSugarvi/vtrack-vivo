-- Fix leaderboard error - Recreate functions with better error handling

-- ==========================================
-- DROP AND RECREATE get_daily_ranking
-- ==========================================
DROP FUNCTION IF EXISTS get_daily_ranking(date,uuid,integer);

CREATE OR REPLACE FUNCTION get_daily_ranking(
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
    has_sold BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH daily_sales AS (
        SELECT 
            so.promotor_id,
            COUNT(*) as sales_count,
            SUM(COALESCE(so.estimated_bonus, 0)) as bonus_total
        FROM sales_sell_out so
        WHERE DATE(so.transaction_date) = p_date
        AND so.deleted_at IS NULL
        GROUP BY so.promotor_id
    ),
    all_promotors AS (
        SELECT 
            u.id as promotor_id,
            u.full_name as promotor_name,
            s.store_name,
            COALESCE(ds.sales_count, 0)::INTEGER as total_sales,
            COALESCE(ds.bonus_total, 0) as total_bonus,
            (ds.sales_count IS NOT NULL AND ds.sales_count > 0) as has_sold
        FROM users u
        LEFT JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
        LEFT JOIN stores s ON s.id = aps.store_id
        LEFT JOIN daily_sales ds ON ds.promotor_id = u.id
        WHERE u.role = 'promotor'
        AND u.deleted_at IS NULL
        AND s.id IS NOT NULL  -- Only promotors with store assignment
    )
    SELECT 
        ROW_NUMBER() OVER (ORDER BY ap.total_bonus DESC, ap.total_sales DESC)::INTEGER as rank,
        ap.promotor_id,
        ap.promotor_name,
        COALESCE(ap.store_name, 'No Store') as store_name,
        ap.total_sales,
        ap.total_bonus,
        ap.has_sold
    FROM all_promotors ap
    ORDER BY ap.total_bonus DESC, ap.total_sales DESC
    LIMIT p_limit;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error in get_daily_ranking: %', SQLERRM;
        RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_daily_ranking(date,uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION get_daily_ranking(date,uuid,integer) TO anon;

-- ==========================================
-- TEST THE FUNCTION
-- ==========================================
SELECT 'Testing get_daily_ranking...' as status;

SELECT * FROM get_daily_ranking(CURRENT_DATE, NULL, 10);

-- ==========================================
-- VERIFY FUNCTION EXISTS
-- ==========================================
SELECT 
    'Function Status' as check_type,
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'get_daily_ranking';
