-- Fix leaderboard functions to use assignments_promotor_store instead of users.store_id
-- CORRECTED: stores.area is TEXT not area_id, users table has no avatar_url

-- ==========================================
-- DROP EXISTING FUNCTIONS
-- ==========================================
DROP FUNCTION IF EXISTS get_daily_ranking(date,uuid,integer);
DROP FUNCTION IF EXISTS get_live_feed(uuid,date,integer,integer);

-- ==========================================
-- 1. FIX: GET DAILY RANKING
-- ==========================================
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
            SUM(so.estimated_bonus) as bonus_total
        FROM sales_sell_out so
        WHERE so.transaction_date = p_date
        GROUP BY so.promotor_id
    ),
    all_promotors AS (
        SELECT 
            u.id as promotor_id,
            u.full_name as promotor_name,
            s.store_name,
            COALESCE(ds.sales_count, 0)::INTEGER as total_sales,
            COALESCE(ds.bonus_total, 0) as total_bonus,
            (ds.sales_count IS NOT NULL) as has_sold
        FROM users u
        JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
        JOIN stores s ON s.id = aps.store_id
        LEFT JOIN daily_sales ds ON ds.promotor_id = u.id
        WHERE u.role = 'promotor'
        AND u.deleted_at IS NULL
    )
    SELECT 
        ROW_NUMBER() OVER (ORDER BY ap.total_bonus DESC, ap.total_sales DESC)::INTEGER as rank,
        ap.promotor_id,
        ap.promotor_name,
        ap.store_name,
        ap.total_sales,
        ap.total_bonus,
        ap.has_sold
    FROM all_promotors ap
    ORDER BY ap.total_bonus DESC, ap.total_sales DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 2. FIX: GET LIVE FEED
-- ==========================================
CREATE OR REPLACE FUNCTION get_live_feed(
    p_user_id UUID,
    p_date DATE DEFAULT CURRENT_DATE,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    feed_id UUID,
    feed_type TEXT,
    sale_id UUID,
    promotor_id UUID,
    promotor_name TEXT,
    store_name TEXT,
    product_name TEXT,
    variant_name TEXT,
    price NUMERIC,
    bonus NUMERIC,
    payment_method TEXT,
    leasing_provider TEXT,
    customer_type TEXT,
    notes TEXT,
    image_url TEXT,
    reaction_counts JSONB,
    user_reactions TEXT[],
    comment_count INTEGER,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    v_user_role TEXT;
    v_user_area TEXT;
BEGIN
    -- Get user role and area
    SELECT u.role, u.area INTO v_user_role, v_user_area
    FROM users u
    WHERE u.id = p_user_id;
    
    RETURN QUERY
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
        so.customer_type::TEXT,
        so.notes,
        so.image_proof_url as image_url,
        -- Reaction counts
        COALESCE(
            (
                SELECT jsonb_object_agg(fr.reaction_type, fr.count)
                FROM (
                    SELECT fr.reaction_type, COUNT(*)::INTEGER as count
                    FROM feed_reactions fr
                    WHERE fr.sale_id = so.id
                    GROUP BY fr.reaction_type
                ) fr
            ),
            '{}'::jsonb
        ) as reaction_counts,
        -- User's reactions
        COALESCE(
            (
                SELECT array_agg(fr.reaction_type)
                FROM feed_reactions fr
                WHERE fr.sale_id = so.id AND fr.user_id = p_user_id
            ),
            ARRAY[]::TEXT[]
        ) as user_reactions,
        -- Comment count
        COALESCE(
            (
                SELECT COUNT(*)::INTEGER
                FROM feed_comments fc
                WHERE fc.sale_id = so.id AND fc.deleted_at IS NULL
            ),
            0
        ) as comment_count,
        so.created_at
    FROM sales_sell_out so
    JOIN users u ON u.id = so.promotor_id
    JOIN stores st ON st.id = so.store_id
    JOIN product_variants pv ON pv.id = so.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE so.transaction_date = p_date
    AND so.deleted_at IS NULL
    -- Filter by area for promotor role (same area only)
    AND (v_user_role != 'promotor' OR st.area = v_user_area)
    ORDER BY so.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
