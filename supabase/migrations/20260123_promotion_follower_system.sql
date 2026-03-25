-- Promotion and Follower Reporting System
-- Based on docs/03_UI_PROMOTOR_ROLE.md and docs/REPORTING_STRUCTURE.md

-- ==========================================
-- 1. PROMOTION REPORTS TABLE
-- ==========================================
CREATE TABLE promotion_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES stores(id),
    
    -- Platform: tiktok, instagram, facebook, whatsapp, youtube
    platform TEXT NOT NULL CHECK (platform IN ('tiktok', 'instagram', 'facebook', 'whatsapp', 'youtube')),
    
    -- Content details
    post_url TEXT, -- Link to the post
    screenshot_urls TEXT[], -- Array of Cloudinary URLs
    notes TEXT,
    
    -- Metrics (optional)
    views_count INTEGER,
    likes_count INTEGER,
    comments_count INTEGER,
    shares_count INTEGER,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'approved', 'rejected')),
    
    -- Timestamps
    posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes
CREATE INDEX idx_promotion_reports_promotor ON promotion_reports(promotor_id);
CREATE INDEX idx_promotion_reports_platform ON promotion_reports(platform);
CREATE INDEX idx_promotion_reports_posted_at ON promotion_reports(posted_at);
CREATE INDEX idx_promotion_reports_status ON promotion_reports(status);

-- ==========================================
-- 2. FOLLOWER REPORTS TABLE
-- ==========================================
CREATE TABLE follower_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES stores(id),
    
    -- Platform (mainly TikTok, but can extend)
    platform TEXT NOT NULL DEFAULT 'tiktok' CHECK (platform IN ('tiktok', 'instagram', 'facebook', 'youtube')),
    
    -- Follower details
    username TEXT NOT NULL, -- Auto-add @ prefix if not present
    screenshot_url TEXT, -- Cloudinary URL
    notes TEXT,
    
    -- Current follower count (optional)
    follower_count INTEGER,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'approved', 'rejected')),
    
    -- Timestamps
    followed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes
CREATE INDEX idx_follower_reports_promotor ON follower_reports(promotor_id);
CREATE INDEX idx_follower_reports_platform ON follower_reports(platform);
CREATE INDEX idx_follower_reports_followed_at ON follower_reports(followed_at);
CREATE INDEX idx_follower_reports_username ON follower_reports(username);

-- ==========================================
-- 3. RLS POLICIES
-- ==========================================
ALTER TABLE promotion_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE follower_reports ENABLE ROW LEVEL SECURITY;

-- Promotor can manage their own reports
CREATE POLICY "Promotor can manage own promotion reports" ON promotion_reports
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

CREATE POLICY "Promotor can manage own follower reports" ON follower_reports
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- SATOR can view reports from their team
CREATE POLICY "SATOR can view team promotion reports" ON promotion_reports
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = promotion_reports.promotor_id
            AND hsp.active = true
        )
    );

CREATE POLICY "SATOR can view team follower reports" ON follower_reports
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = follower_reports.promotor_id
            AND hsp.active = true
        )
    );

-- SPV can view reports in their area
CREATE POLICY "SPV can view area promotion reports" ON promotion_reports
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = promotion_reports.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

CREATE POLICY "SPV can view area follower reports" ON follower_reports
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = follower_reports.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

-- Admin can manage all reports
CREATE POLICY "Admin can manage all promotion reports" ON promotion_reports
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

CREATE POLICY "Admin can manage all follower reports" ON follower_reports
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- ==========================================
-- 4. TRIGGERS
-- ==========================================
CREATE OR REPLACE FUNCTION update_promotion_reports_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_promotion_reports_updated_at
    BEFORE UPDATE ON promotion_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_promotion_reports_updated_at();

CREATE OR REPLACE FUNCTION update_follower_reports_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_follower_reports_updated_at
    BEFORE UPDATE ON follower_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_follower_reports_updated_at();

-- ==========================================
-- 5. HELPER FUNCTIONS
-- ==========================================

-- Function to get promotion summary for promotor
CREATE OR REPLACE FUNCTION get_promotion_summary(
    p_promotor_id UUID,
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
        'total_posts', COUNT(*),
        'tiktok_posts', COUNT(*) FILTER (WHERE platform = 'tiktok'),
        'instagram_posts', COUNT(*) FILTER (WHERE platform = 'instagram'),
        'facebook_posts', COUNT(*) FILTER (WHERE platform = 'facebook'),
        'whatsapp_posts', COUNT(*) FILTER (WHERE platform = 'whatsapp'),
        'youtube_posts', COUNT(*) FILTER (WHERE platform = 'youtube'),
        'total_views', SUM(views_count),
        'total_likes', SUM(likes_count),
        'period_start', v_start_date,
        'period_end', v_end_date
    ) INTO v_summary
    FROM promotion_reports
    WHERE promotor_id = p_promotor_id
    AND posted_at::DATE BETWEEN v_start_date AND v_end_date;
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get follower summary for promotor
CREATE OR REPLACE FUNCTION get_follower_summary(
    p_promotor_id UUID,
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
        'total_followers', COUNT(*),
        'tiktok_followers', COUNT(*) FILTER (WHERE platform = 'tiktok'),
        'instagram_followers', COUNT(*) FILTER (WHERE platform = 'instagram'),
        'facebook_followers', COUNT(*) FILTER (WHERE platform = 'facebook'),
        'youtube_followers', COUNT(*) FILTER (WHERE platform = 'youtube'),
        'period_start', v_start_date,
        'period_end', v_end_date
    ) INTO v_summary
    FROM follower_reports
    WHERE promotor_id = p_promotor_id
    AND followed_at::DATE BETWEEN v_start_date AND v_end_date;
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_promotion_summary TO authenticated;
GRANT EXECUTE ON FUNCTION get_follower_summary TO authenticated;

-- Add comments
COMMENT ON TABLE promotion_reports IS 'Social media promotion reports by promotors';
COMMENT ON TABLE follower_reports IS 'New follower reports by promotors';
COMMENT ON FUNCTION get_promotion_summary IS 'Get promotion summary for a promotor in a date range';
COMMENT ON FUNCTION get_follower_summary IS 'Get follower summary for a promotor in a date range';
