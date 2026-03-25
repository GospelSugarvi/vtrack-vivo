-- 0. Helper Function: Get Time-Gone Percentage
CREATE OR REPLACE FUNCTION get_time_gone_percentage(p_period_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_days INTEGER;
    v_days_passed INTEGER;
    v_percentage NUMERIC;
BEGIN
    SELECT start_date, end_date 
    INTO v_start_date, v_end_date
    FROM target_periods
    WHERE id = p_period_id;
    
    IF v_start_date IS NULL THEN RETURN 0; END IF;
    
    v_total_days := v_end_date - v_start_date + 1;
    v_days_passed := LEAST(CURRENT_DATE - v_start_date + 1, v_total_days);
    v_days_passed := GREATEST(v_days_passed, 0);
    
    IF v_total_days > 0 THEN
        v_percentage := (v_days_passed::NUMERIC / v_total_days::NUMERIC) * 100;
    ELSE
        v_percentage := 0;
    END IF;
    
    RETURN ROUND(v_percentage, 2);
END;
$$ LANGUAGE plpgsql STABLE;

-- 1. Create function to calculate weekly breakdown
CREATE OR REPLACE FUNCTION calculate_weekly_breakdown(
    p_user_id UUID,
    p_period_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_total_target NUMERIC;
    v_period_start DATE;
    v_result JSONB;
BEGIN
    -- Get total target for the period
    SELECT COALESCE(target_omzet, 0) INTO v_total_target
    FROM user_targets
    WHERE user_id = p_user_id AND period_id = p_period_id;
    
    -- Get period start date
    SELECT start_date INTO v_period_start
    FROM target_periods
    WHERE id = p_period_id;

    IF v_period_start IS NULL OR v_total_target = 0 THEN
        RETURN '[]'::JSONB;
    END IF;

    -- Calculate achievement per week
    SELECT jsonb_agg(
        jsonb_build_object(
            'week_number', wt.week_number,
            'start_date', (v_period_start + (wt.start_day - 1) * INTERVAL '1 day')::DATE,
            'end_date', (v_period_start + (wt.end_day - 1) * INTERVAL '1 day')::DATE,
            'target_omzet', ROUND((v_total_target * wt.percentage / 100.0), 0),
            'actual_omzet', COALESCE(
                (SELECT SUM(price_at_transaction)
                 FROM sales_sell_out
                 WHERE promotor_id = p_user_id
                 AND transaction_date >= (v_period_start + (wt.start_day - 1) * INTERVAL '1 day')::DATE
                 AND transaction_date <= (v_period_start + (wt.end_day - 1) * INTERVAL '1 day')::DATE
                ), 0
            ),
            'achievement_pct', CASE 
                WHEN (v_total_target * wt.percentage / 100.0) > 0 
                THEN ROUND((COALESCE(
                    (SELECT SUM(price_at_transaction)
                     FROM sales_sell_out
                     WHERE promotor_id = p_user_id
                     AND transaction_date >= (v_period_start + (wt.start_day - 1) * INTERVAL '1 day')::DATE
                     AND transaction_date <= (v_period_start + (wt.end_day - 1) * INTERVAL '1 day')::DATE
                    ), 0
                ) / (v_total_target * wt.percentage / 100.0) * 100), 2)
                ELSE 0
            END,
            'percentage_of_total', wt.percentage
        )
        ORDER BY wt.week_number
    )
    INTO v_result
    FROM weekly_targets wt;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. Update calculate_target_achievement to include weekly_breakdown
-- We must drop dependent objects first
DROP MATERIALIZED VIEW IF EXISTS v_target_dashboard CASCADE;
DROP FUNCTION IF EXISTS get_target_dashboard(uuid,uuid);
DROP FUNCTION IF EXISTS calculate_target_achievement(uuid,uuid);

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
    
    -- Weekly Breakdown (New!)
    weekly_breakdown JSONB,
    
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
    v_weekly_breakdown JSONB;
BEGIN
    -- Get time-gone percentage
    v_time_gone := get_time_gone_percentage(p_period_id);
    
    -- Get target omzet (All Type)
    -- FIXED: Use target_omzet (standard name) instead of target_omzet_all
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
    
    -- Get weekly breakdown
    v_weekly_breakdown := calculate_weekly_breakdown(p_user_id, p_period_id);
    
    -- Return results
    RETURN QUERY SELECT
        v_target_omzet,
        v_actual_omzet,
        ROUND(v_achievement_omzet, 2),
        v_target_fokus,
        v_actual_fokus,
        ROUND(v_achievement_fokus, 2),
        v_fokus_details,
        v_weekly_breakdown,
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

-- 3. Recreate v_target_dashboard with new schema
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

CREATE INDEX idx_v_target_dashboard_user ON v_target_dashboard(user_id);
CREATE INDEX idx_v_target_dashboard_period ON v_target_dashboard(period_id);

-- 4. Update get_target_dashboard return type
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
    weekly_breakdown JSONB,
    time_gone_pct NUMERIC,
    status_omzet TEXT,
    status_fokus TEXT,
    warning_omzet BOOLEAN,
    warning_fokus BOOLEAN
) AS $$
BEGIN
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
            vtd.weekly_breakdown,
            vtd.time_gone_pct,
            vtd.status_omzet,
            vtd.status_fokus,
            vtd.warning_omzet,
            vtd.warning_fokus
        FROM v_target_dashboard vtd
        WHERE vtd.user_id = p_user_id
        AND vtd.period_id = p_period_id;
    ELSE
        -- Get current month's period
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
            vtd.weekly_breakdown,
            vtd.time_gone_pct,
            vtd.status_omzet,
            vtd.status_fokus,
            vtd.warning_omzet,
            vtd.warning_fokus
        FROM v_target_dashboard vtd
        JOIN target_periods tp ON tp.id = vtd.period_id
        WHERE vtd.user_id = p_user_id
        AND tp.target_month = EXTRACT(MONTH FROM CURRENT_DATE)
        AND tp.target_year = EXTRACT(YEAR FROM CURRENT_DATE)
        AND tp.deleted_at IS NULL
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Grant permissions (just in case)
GRANT SELECT ON v_target_dashboard TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_weekly_breakdown(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_target_dashboard(UUID, UUID) TO authenticated;

-- Initial refresh
REFRESH MATERIALIZED VIEW v_target_dashboard;
