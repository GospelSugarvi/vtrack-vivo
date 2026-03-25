-- AllBrand (Competitor Analysis) System
-- Based on docs/03_UI_PROMOTOR_ROLE.md and docs/_archive/PROMOTOR_FEATURES_COMPLETE.md

-- ==========================================
-- 1. ALLBRAND REPORTS TABLE
-- ==========================================
CREATE TABLE allbrand_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES stores(id),
    
    -- Report date
    report_date DATE NOT NULL DEFAULT CURRENT_DATE,
    
    -- Brand data (JSONB for flexibility)
    -- Structure: { "brand_name": { "under_2m": 5, "2m_4m": 8, "4m_6m": 3, "above_6m": 2, "promotor_count": 2 } }
    brand_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    
    -- Leasing sales data (JSONB)
    -- Structure: { "HCI": 5, "Kredivo": 3, "FIF": 2, "VAST Finance": 1, "Kredit Plus": 0, "Indodana": 0, "Home Credit": 0 }
    leasing_sales JSONB DEFAULT '{}'::jsonb,
    
    -- VIVO data (auto-calculated from system)
    vivo_auto_data JSONB,
    
    -- VIVO promotor count (manual input)
    vivo_promotor_count INTEGER,
    
    -- Notes
    notes TEXT,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted', 'approved', 'rejected')),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Constraint: One report per promotor per store per day
    UNIQUE(promotor_id, store_id, report_date)
);

-- Add indexes
CREATE INDEX idx_allbrand_reports_promotor ON allbrand_reports(promotor_id);
CREATE INDEX idx_allbrand_reports_store ON allbrand_reports(store_id);
CREATE INDEX idx_allbrand_reports_date ON allbrand_reports(report_date);
CREATE INDEX idx_allbrand_reports_status ON allbrand_reports(status);

-- ==========================================
-- 2. RLS POLICIES
-- ==========================================
ALTER TABLE allbrand_reports ENABLE ROW LEVEL SECURITY;

-- Promotor can manage their own reports
CREATE POLICY "Promotor can manage own allbrand reports" ON allbrand_reports
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- SATOR can view reports from their team
CREATE POLICY "SATOR can view team allbrand reports" ON allbrand_reports
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = allbrand_reports.promotor_id
            AND hsp.active = true
        )
    );

-- SPV can view reports in their area
CREATE POLICY "SPV can view area allbrand reports" ON allbrand_reports
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = allbrand_reports.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

-- Admin can manage all reports
CREATE POLICY "Admin can manage all allbrand reports" ON allbrand_reports
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- ==========================================
-- 3. TRIGGERS
-- ==========================================
CREATE OR REPLACE FUNCTION update_allbrand_reports_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_allbrand_reports_updated_at
    BEFORE UPDATE ON allbrand_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_allbrand_reports_updated_at();

-- ==========================================
-- 4. HELPER FUNCTIONS
-- ==========================================

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
        'under_2m', COUNT(*) FILTER (WHERE pv.price < 2000000),
        '2m_4m', COUNT(*) FILTER (WHERE pv.price >= 2000000 AND pv.price < 4000000),
        '4m_6m', COUNT(*) FILTER (WHERE pv.price >= 4000000 AND pv.price < 6000000),
        'above_6m', COUNT(*) FILTER (WHERE pv.price >= 6000000),
        'total', COUNT(*)
    ) INTO v_result
    FROM sell_out so
    JOIN stok s ON s.imei = so.imei
    JOIN product_variants pv ON pv.id = s.variant_id
    WHERE so.store_id = p_store_id
    AND so.sold_at::DATE = p_date;
    
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
COMMENT ON TABLE allbrand_reports IS 'Competitor brand analysis reports by promotors';
COMMENT ON FUNCTION get_vivo_auto_data IS 'Get VIVO sales data auto-calculated from system';
COMMENT ON FUNCTION has_allbrand_report_today IS 'Check if promotor has submitted allbrand report today';
COMMENT ON FUNCTION get_allbrand_summary IS 'Get allbrand summary for a store in a date range';
