-- Fix Target Dashboard - Fokus Details Calculation
-- Problem: Using non-existent fokus_bundle_products table
-- Solution: Use fokus_bundles.product_types array to match products

-- ==========================================
-- STEP 0: Create helper function get_time_gone_percentage
-- ==========================================
CREATE OR REPLACE FUNCTION get_time_gone_percentage(p_period_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_days INTEGER;
    v_days_gone INTEGER;
    v_percentage NUMERIC;
BEGIN
    -- Get period dates
    SELECT start_date, end_date
    INTO v_start_date, v_end_date
    FROM target_periods
    WHERE id = p_period_id;
    
    -- If period not found, return 0
    IF v_start_date IS NULL OR v_end_date IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Calculate total days in period
    v_total_days := v_end_date - v_start_date + 1;
    
    -- Calculate days gone (from start to today, capped at end_date)
    v_days_gone := LEAST(CURRENT_DATE, v_end_date) - v_start_date + 1;
    
    -- Ensure days_gone is at least 1 and not more than total_days
    v_days_gone := GREATEST(1, LEAST(v_days_gone, v_total_days));
    
    -- Calculate percentage
    IF v_total_days > 0 THEN
        v_percentage := (v_days_gone::NUMERIC / v_total_days::NUMERIC) * 100;
    ELSE
        v_percentage := 0;
    END IF;
    
    RETURN ROUND(v_percentage, 2);
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- STEP 1: Fix calculate_target_achievement function
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_target_achievement(
    p_user_id UUID,
    p_period_id UUID
)
RETURNS TABLE (
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
DECLARE
    v_target_omzet NUMERIC := 0;
    v_actual_omzet NUMERIC := 0;
    v_achievement_omzet NUMERIC := 0;
    v_target_fokus INTEGER := 0;
    v_actual_fokus INTEGER := 0;
    v_achievement_fokus NUMERIC := 0;
    v_fokus_details JSONB := '[]'::jsonb;
    v_time_gone NUMERIC := 0;
BEGIN
    -- Get time gone percentage
    SELECT COALESCE(get_time_gone_percentage(p_period_id), 0)
    INTO v_time_gone;
    
    -- Get target omzet
    SELECT COALESCE(target_omzet, 0)
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
    
    -- Get fokus details (per bundle)
    -- FIXED: Use fokus_bundles.product_types array instead of junction table
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'bundle_id', ft.bundle_id,
                'bundle_name', fb.bundle_name,
                'product_types', fb.product_types,
                'target_qty', ft.target_qty,
                'actual_qty', COALESCE(
                    (
                        SELECT COUNT(*)
                        FROM sales_sell_out so
                        JOIN product_variants pv ON so.variant_id = pv.id
                        JOIN products p ON pv.product_id = p.id
                        WHERE so.promotor_id = p_user_id
                        AND p.model_name = ANY(fb.product_types)
                        AND so.transaction_date >= (SELECT start_date FROM target_periods WHERE id = p_period_id)
                        AND so.transaction_date <= (SELECT end_date FROM target_periods WHERE id = p_period_id)
                        AND so.deleted_at IS NULL
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
                                    JOIN products p ON pv.product_id = p.id
                                    WHERE so.promotor_id = p_user_id
                                    AND p.model_name = ANY(fb.product_types)
                                    AND so.transaction_date >= (SELECT start_date FROM target_periods WHERE id = p_period_id)
                                    AND so.transaction_date <= (SELECT end_date FROM target_periods WHERE id = p_period_id)
                                    AND so.deleted_at IS NULL
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

-- ==========================================
-- STEP 2: Create/Recreate materialized view
-- ==========================================
DROP MATERIALIZED VIEW IF EXISTS v_target_dashboard CASCADE;

CREATE MATERIALIZED VIEW v_target_dashboard AS
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

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_v_target_dashboard_user ON v_target_dashboard(user_id);
CREATE INDEX IF NOT EXISTS idx_v_target_dashboard_period ON v_target_dashboard(period_id);
CREATE INDEX IF NOT EXISTS idx_v_target_dashboard_warnings ON v_target_dashboard(warning_omzet, warning_fokus);

-- ==========================================
-- STEP 3: Refresh materialized view
-- ==========================================
REFRESH MATERIALIZED VIEW v_target_dashboard;

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Target dashboard fokus details fixed!' as status;
SELECT 'Now using fokus_bundles.product_types array correctly' as note;
