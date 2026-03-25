-- Migration: Target Achievement System with Time-Gone Analysis
-- Purpose: Calculate target vs actual with time-gone comparison
-- Date: 24 Januari 2026

-- ==========================================
-- 1. FUNCTION: Get Time-Gone Percentage
-- ==========================================
-- Must be created FIRST before calculate_target_achievement
CREATE OR REPLACE FUNCTION get_time_gone_percentage(p_period_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_days INTEGER;
    v_days_passed INTEGER;
    v_percentage NUMERIC;
BEGIN
    -- Get period dates
    SELECT start_date, end_date 
    INTO v_start_date, v_end_date
    FROM target_periods
    WHERE id = p_period_id;
    
    IF v_start_date IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Calculate total days in period
    v_total_days := v_end_date - v_start_date + 1;
    
    -- Calculate days passed
    v_days_passed := LEAST(CURRENT_DATE - v_start_date + 1, v_total_days);
    v_days_passed := GREATEST(v_days_passed, 0);
    
    -- Calculate percentage
    IF v_total_days > 0 THEN
        v_percentage := (v_days_passed::NUMERIC / v_total_days::NUMERIC) * 100;
    ELSE
        v_percentage := 0;
    END IF;
    
    RETURN ROUND(v_percentage, 2);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_time_gone_percentage(UUID) IS 'Calculate how much time has passed in the period (%)';

-- ==========================================
-- 2. FUNCTION: Calculate Target Achievement
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_target_achievement(
    p_user_id UUID,
    p_period_id UUID
)
RETURNS TABLE (
    -- All Type Target
    target_omzet NUMERIC,
    actual_omzet NUMERIC,
    achievement_omzet_pct NUMERIC,
    
    -- Fokus Target (Total)
    target_fokus_total INTEGER,
    actual_fokus_total INTEGER,
    achievement_fokus_pct NUMERIC,
    
    -- Fokus Detail (per product)
    fokus_details JSONB,
    
    -- Time Analysis
    time_gone_pct NUMERIC,
    status_omzet TEXT,
    status_fokus TEXT,
    
    -- Warnings
    warning_omzet BOOLEAN,
    warning_fokus BOOLEAN
) AS $$
DECLARE
    v_time_gone NUMERIC;
    v_target_omzet NUMERIC;
    v_actual_omzet NUMERIC;
    v_achievement_omzet NUMERIC;
    v_target_fokus INTEGER;
    v_actual_fokus INTEGER;
    v_achievement_fokus NUMERIC;
    v_fokus_details JSONB;
BEGIN
    -- Get time-gone percentage
    v_time_gone := get_time_gone_percentage(p_period_id);
    
    -- Get target omzet (All Type)
    SELECT COALESCE(target_omzet_all, 0)
    INTO v_target_omzet
    FROM user_targets
    WHERE user_id = p_user_id AND period_id = p_period_id;
    
    v_target_omzet := COALESCE(v_target_omzet, 0);
    
    -- Get actual omzet from dashboard_performance_metrics
    SELECT COALESCE(total_omzet_real, 0)
    INTO v_actual_omzet
    FROM dashboard_performance_metrics
    WHERE user_id = p_user_id AND period_id = p_period_id;
    
    v_actual_omzet := COALESCE(v_actual_omzet, 0);
    
    -- Calculate achievement percentage
    IF v_target_omzet > 0 THEN
        v_achievement_omzet := (v_actual_omzet / v_target_omzet) * 100;
    ELSE
        v_achievement_omzet := 0;
    END IF;
    
    -- Get target fokus total
    SELECT COALESCE(target_fokus_total, 0)
    INTO v_target_fokus
    FROM user_targets
    WHERE user_id = p_user_id AND period_id = p_period_id;
    
    v_target_fokus := COALESCE(v_target_fokus, 0);
    
    -- Get actual fokus from dashboard_performance_metrics
    SELECT COALESCE(total_units_focus, 0)
    INTO v_actual_fokus
    FROM dashboard_performance_metrics
    WHERE user_id = p_user_id AND period_id = p_period_id;
    
    v_actual_fokus := COALESCE(v_actual_fokus, 0);
    
    -- Calculate fokus achievement
    IF v_target_fokus > 0 THEN
        v_achievement_fokus := (v_actual_fokus::NUMERIC / v_target_fokus::NUMERIC) * 100;
    ELSE
        v_achievement_fokus := 0;
    END IF;
    
    -- Get fokus details (per product)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'bundle_id', ft.bundle_id,
                'bundle_name', fb.bundle_name,
                'target_qty', ft.target_qty,
                'actual_qty', COALESCE(
                    (
                        SELECT COUNT(*)
                        FROM sales_sell_out so
                        JOIN product_variants pv ON so.variant_id = pv.id
                        JOIN fokus_bundle_products fbp ON fbp.product_id = pv.product_id
                        WHERE so.promotor_id = p_user_id
                        AND fbp.bundle_id = ft.bundle_id
                        AND so.transaction_date >= (SELECT start_date FROM target_periods WHERE id = p_period_id)
                        AND so.transaction_date <= (SELECT end_date FROM target_periods WHERE id = p_period_id)
                    ), 0
                ),
                'achievement_pct', CASE 
                    WHEN ft.target_qty > 0 THEN 
                        ROUND((
                            COALESCE(
                                (
                                    SELECT COUNT(*)
                                    FROM sales_sell_out so
                                    JOIN product_variants pv ON so.variant_id = pv.id
                                    JOIN fokus_bundle_products fbp ON fbp.product_id = pv.product_id
                                    WHERE so.promotor_id = p_user_id
                                    AND fbp.bundle_id = ft.bundle_id
                                    AND so.transaction_date >= (SELECT start_date FROM target_periods WHERE id = p_period_id)
                                    AND so.transaction_date <= (SELECT end_date FROM target_periods WHERE id = p_period_id)
                                ), 0
                            )::NUMERIC / ft.target_qty::NUMERIC
                        ) * 100, 2)
                    ELSE 0
                END
            )
        ),
        '[]'::jsonb
    )
    INTO v_fokus_details
    FROM fokus_targets ft
    JOIN fokus_bundles fb ON ft.bundle_id = fb.id
    WHERE ft.user_id = p_user_id AND ft.period_id = p_period_id;
    
    -- Return results
    RETURN QUERY SELECT
        v_target_omzet,
        v_actual_omzet,
        ROUND(v_achievement_omzet, 2),
        v_target_fokus,
        v_actual_fokus,
        ROUND(v_achievement_fokus, 2),
        v_fokus_details,
        v_time_gone,
        -- Status omzet
        CASE 
            WHEN v_achievement_omzet >= 100 THEN 'ACHIEVED'
            WHEN v_achievement_omzet >= v_time_gone THEN 'ON_TRACK'
            ELSE 'WARNING'
        END,
        -- Status fokus
        CASE 
            WHEN v_achievement_fokus >= 100 THEN 'ACHIEVED'
            WHEN v_achievement_fokus >= v_time_gone THEN 'ON_TRACK'
            ELSE 'WARNING'
        END,
        -- Warning flags
        (v_achievement_omzet < v_time_gone AND v_target_omzet > 0),
        (v_achievement_fokus < v_time_gone AND v_target_fokus > 0);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION calculate_target_achievement IS 'Calculate target achievement with time-gone analysis';

-- ==========================================
-- 3. VIEW: Target Dashboard (Materialized for performance)
-- ==========================================
CREATE MATERIALIZED VIEW IF NOT EXISTS v_target_dashboard AS
SELECT 
    u.id as user_id,
    u.full_name,
    u.role,
    tp.id as period_id,
    tp.period_name,
    tp.start_date,
    tp.end_date,
    ta.*
FROM users u
CROSS JOIN target_periods tp
LEFT JOIN LATERAL calculate_target_achievement(u.id, tp.id) ta ON true
WHERE u.deleted_at IS NULL
AND tp.deleted_at IS NULL
AND u.role IN ('promotor', 'sator', 'spv');

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_v_target_dashboard_user ON v_target_dashboard(user_id);
CREATE INDEX IF NOT EXISTS idx_v_target_dashboard_period ON v_target_dashboard(period_id);
CREATE INDEX IF NOT EXISTS idx_v_target_dashboard_warnings ON v_target_dashboard(warning_omzet, warning_fokus);

COMMENT ON MATERIALIZED VIEW v_target_dashboard IS 'Cached target achievement data for all users';

-- ==========================================
-- 4. FUNCTION: Refresh Target Dashboard
-- ==========================================
CREATE OR REPLACE FUNCTION refresh_target_dashboard()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY v_target_dashboard;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION refresh_target_dashboard IS 'Refresh target dashboard cache';

-- ==========================================
-- 5. FUNCTION: Get Target Dashboard for User
-- ==========================================
CREATE OR REPLACE FUNCTION get_target_dashboard(
    p_user_id UUID,
    p_period_id UUID DEFAULT NULL
)
RETURNS TABLE (
    period_id UUID,
    period_name TEXT,
    start_date DATE,
    end_date DATE,
    target_omzet NUMERIC,
    actual_omzet NUMERIC,
    achievement_omzet_pct NUMERIC,
    target_fokus_total INTEGER,
    actual_fokus_total INTEGER,
    achievement_fokus_pct NUMERIC,
    fokus_details JSONB,
    time_gone_pct NUMERIC,
    status_omzet TEXT,
    status_fokus TEXT,
    warning_omzet BOOLEAN,
    warning_fokus BOOLEAN
) AS $$
BEGIN
    -- If period_id specified, get that period only
    IF p_period_id IS NOT NULL THEN
        RETURN QUERY
        SELECT 
            vtd.period_id,
            vtd.period_name,
            vtd.start_date,
            vtd.end_date,
            vtd.target_omzet,
            vtd.actual_omzet,
            vtd.achievement_omzet_pct,
            vtd.target_fokus_total,
            vtd.actual_fokus_total,
            vtd.achievement_fokus_pct,
            vtd.fokus_details,
            vtd.time_gone_pct,
            vtd.status_omzet,
            vtd.status_fokus,
            vtd.warning_omzet,
            vtd.warning_fokus
        FROM v_target_dashboard vtd
        WHERE vtd.user_id = p_user_id
        AND vtd.period_id = p_period_id;
    ELSE
        -- Get current period (most recent active period)
        RETURN QUERY
        SELECT 
            vtd.period_id,
            vtd.period_name,
            vtd.start_date,
            vtd.end_date,
            vtd.target_omzet,
            vtd.actual_omzet,
            vtd.achievement_omzet_pct,
            vtd.target_fokus_total,
            vtd.actual_fokus_total,
            vtd.achievement_fokus_pct,
            vtd.fokus_details,
            vtd.time_gone_pct,
            vtd.status_omzet,
            vtd.status_fokus,
            vtd.warning_omzet,
            vtd.warning_fokus
        FROM v_target_dashboard vtd
        WHERE vtd.user_id = p_user_id
        AND CURRENT_DATE BETWEEN vtd.start_date AND vtd.end_date
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_target_dashboard IS 'Get target dashboard for specific user and period';

-- ==========================================
-- 6. GRANT PERMISSIONS
-- ==========================================
GRANT EXECUTE ON FUNCTION get_time_gone_percentage(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_target_achievement(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_target_dashboard(UUID, UUID) TO authenticated;
GRANT SELECT ON v_target_dashboard TO authenticated;

-- ==========================================
-- 7. INITIAL REFRESH
-- ==========================================
REFRESH MATERIALIZED VIEW v_target_dashboard;
