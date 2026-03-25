-- Leaderboard System: Reactions, Comments, and Feed Functions
-- Based on docs/03_UI_PROMOTOR_ROLE.md and docs/03_UI_SATOR_ROLE.md

-- ==========================================
-- 1. REACTIONS TABLE
-- ==========================================
CREATE TABLE feed_reactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES sales_sell_out(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  reaction_type TEXT NOT NULL CHECK (reaction_type IN ('clap', 'fire', 'muscle')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(sale_id, user_id, reaction_type)
);

CREATE INDEX idx_feed_reactions_sale ON feed_reactions(sale_id);
CREATE INDEX idx_feed_reactions_user ON feed_reactions(user_id);

-- ==========================================
-- 2. COMMENTS TABLE
-- ==========================================
CREATE TABLE feed_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES sales_sell_out(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  comment_text TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_feed_comments_sale ON feed_comments(sale_id);
CREATE INDEX idx_feed_comments_user ON feed_comments(user_id);

-- ==========================================
-- 3. MANUAL POSTS TABLE (for SATOR announcements)
-- ==========================================
CREATE TABLE feed_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  author_id UUID REFERENCES users(id) ON DELETE CASCADE,
  post_type TEXT NOT NULL CHECK (post_type IN ('announcement', 'praise')),
  content TEXT NOT NULL,
  image_url TEXT,
  target_audience TEXT, -- 'all', 'area', 'store'
  target_id UUID, -- area_id or store_id
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_feed_posts_author ON feed_posts(author_id);
CREATE INDEX idx_feed_posts_created ON feed_posts(created_at DESC);

-- ==========================================
-- 4. FUNCTION: GET DAILY RANKING
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
    promotor_avatar TEXT,
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
        AND (p_area_id IS NULL OR EXISTS (
            SELECT 1 FROM stores s 
            WHERE s.id = so.store_id AND s.area_id = p_area_id
        ))
        GROUP BY so.promotor_id
    ),
    all_promotors AS (
        SELECT 
            u.id as promotor_id,
            u.full_name as promotor_name,
            u.avatar_url as promotor_avatar,
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
        AND (p_area_id IS NULL OR s.area_id = p_area_id)
    )
    SELECT 
        ROW_NUMBER() OVER (ORDER BY ap.total_bonus DESC, ap.total_sales DESC)::INTEGER as rank,
        ap.promotor_id,
        ap.promotor_name,
        ap.promotor_avatar,
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
-- 5. FUNCTION: GET LIVE FEED
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
    promotor_avatar TEXT,
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
    v_area_id UUID;
BEGIN
    -- Get user role and area (via store assignment)
    SELECT u.role INTO v_user_role
    FROM users u
    WHERE u.id = p_user_id;
    
    -- Get area_id from store assignment
    SELECT s.area_id INTO v_area_id
    FROM assignments_promotor_store aps
    JOIN stores s ON s.id = aps.store_id
    WHERE aps.promotor_id = p_user_id
    AND aps.active = true
    LIMIT 1;
    
    RETURN QUERY
    SELECT 
        so.id as feed_id,
        'sale'::TEXT as feed_type,
        so.id as sale_id,
        u.id as promotor_id,
        u.full_name as promotor_name,
        u.avatar_url as promotor_avatar,
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
        -- Reaction counts
        (
            SELECT jsonb_object_agg(reaction_type, count)
            FROM (
                SELECT reaction_type, COUNT(*)::INTEGER as count
                FROM feed_reactions
                WHERE sale_id = so.id
                GROUP BY reaction_type
            ) reactions
        ) as reaction_counts,
        -- User's reactions
        (
            SELECT array_agg(reaction_type)
            FROM feed_reactions
            WHERE sale_id = so.id AND user_id = p_user_id
        ) as user_reactions,
        -- Comment count
        (
            SELECT COUNT(*)::INTEGER
            FROM feed_comments
            WHERE sale_id = so.id AND deleted_at IS NULL
        ) as comment_count,
        so.created_at
    FROM sales_sell_out so
    JOIN users u ON u.id = so.promotor_id
    JOIN stores st ON st.id = so.store_id
    JOIN product_variants pv ON pv.id = so.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE so.transaction_date = p_date
    AND so.deleted_at IS NULL
    -- Filter by area for promotor role
    AND (v_user_role != 'promotor' OR st.area_id = v_area_id)
    ORDER BY so.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 6. FUNCTION: TOGGLE REACTION
-- ==========================================
CREATE OR REPLACE FUNCTION toggle_reaction(
    p_sale_id UUID,
    p_user_id UUID,
    p_reaction_type TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    -- Check if reaction exists
    SELECT EXISTS(
        SELECT 1 FROM feed_reactions
        WHERE sale_id = p_sale_id 
        AND user_id = p_user_id 
        AND reaction_type = p_reaction_type
    ) INTO v_exists;
    
    IF v_exists THEN
        -- Remove reaction
        DELETE FROM feed_reactions
        WHERE sale_id = p_sale_id 
        AND user_id = p_user_id 
        AND reaction_type = p_reaction_type;
        RETURN FALSE;
    ELSE
        -- Add reaction
        INSERT INTO feed_reactions (sale_id, user_id, reaction_type)
        VALUES (p_sale_id, p_user_id, p_reaction_type)
        ON CONFLICT (sale_id, user_id, reaction_type) DO NOTHING;
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 7. FUNCTION: GET COMMENTS
-- ==========================================
CREATE OR REPLACE FUNCTION get_sale_comments(
    p_sale_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    comment_id UUID,
    user_id UUID,
    user_name TEXT,
    user_avatar TEXT,
    user_role TEXT,
    comment_text TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fc.id as comment_id,
        u.id as user_id,
        u.full_name as user_name,
        u.avatar_url as user_avatar,
        u.role as user_role,
        fc.comment_text,
        fc.created_at
    FROM feed_comments fc
    JOIN users u ON u.id = fc.user_id
    WHERE fc.sale_id = p_sale_id
    AND fc.deleted_at IS NULL
    ORDER BY fc.created_at ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 8. FUNCTION: ADD COMMENT
-- ==========================================
CREATE OR REPLACE FUNCTION add_comment(
    p_sale_id UUID,
    p_user_id UUID,
    p_comment_text TEXT
)
RETURNS UUID AS $$
DECLARE
    v_comment_id UUID;
BEGIN
    INSERT INTO feed_comments (sale_id, user_id, comment_text)
    VALUES (p_sale_id, p_user_id, p_comment_text)
    RETURNING id INTO v_comment_id;
    
    RETURN v_comment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- RLS POLICIES
-- ==========================================

-- Reactions: authenticated users can read and manage their own
ALTER TABLE feed_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all reactions"
ON feed_reactions FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Users can manage their own reactions"
ON feed_reactions FOR ALL
TO authenticated
USING (user_id = auth.uid());

-- Comments: authenticated users can read all, manage their own
ALTER TABLE feed_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all comments"
ON feed_comments FOR SELECT
TO authenticated
USING (deleted_at IS NULL);

CREATE POLICY "Users can create comments"
ON feed_comments FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own comments"
ON feed_comments FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

-- Posts: authenticated users can read, only sator+ can create
ALTER TABLE feed_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view all posts"
ON feed_posts FOR SELECT
TO authenticated
USING (deleted_at IS NULL);

CREATE POLICY "Sator and above can create posts"
ON feed_posts FOR INSERT
TO authenticated
WITH CHECK (
    author_id = auth.uid() AND
    EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid()
        AND role IN ('sator', 'spv', 'manager', 'admin')
    )
);

-- ==========================================
-- GRANT PERMISSIONS
-- ==========================================
GRANT EXECUTE ON FUNCTION get_daily_ranking TO authenticated;
GRANT EXECUTE ON FUNCTION get_live_feed TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_reaction TO authenticated;
GRANT EXECUTE ON FUNCTION get_sale_comments TO authenticated;
GRANT EXECUTE ON FUNCTION add_comment TO authenticated;

-- ==========================================
-- COMMENTS
-- ==========================================
COMMENT ON TABLE feed_reactions IS 'User reactions (clap, fire, muscle) on sales';
COMMENT ON TABLE feed_comments IS 'Comments on sales in live feed';
COMMENT ON TABLE feed_posts IS 'Manual posts from SATOR/SPV (announcements, praise)';
COMMENT ON FUNCTION get_daily_ranking IS 'Get daily leaderboard ranking by bonus amount';
COMMENT ON FUNCTION get_live_feed IS 'Get live feed of sales with reactions and comments';
COMMENT ON FUNCTION toggle_reaction IS 'Add or remove a reaction on a sale';
COMMENT ON FUNCTION get_sale_comments IS 'Get all comments for a specific sale';
COMMENT ON FUNCTION add_comment IS 'Add a comment to a sale';
