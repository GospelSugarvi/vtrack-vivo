-- Migration: 20260312_fix_target_fokus_total_fallback.sql
-- Ensure target_fokus_total falls back to detail maps when total is zero

-- Ensure get_time_gone_percentage exists (some environments may not have it yet)
CREATE OR REPLACE FUNCTION public.get_time_gone_percentage(p_period_id UUID)
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

    IF v_start_date IS NULL OR v_end_date IS NULL THEN
        RETURN 0;
    END IF;

    v_total_days := (v_end_date - v_start_date) + 1;
    v_days_passed := (CURRENT_DATE - v_start_date) + 1;

    IF v_days_passed < 0 THEN
        v_days_passed := 0;
    ELSIF v_days_passed > v_total_days THEN
        v_days_passed := v_total_days;
    END IF;

    IF v_total_days = 0 THEN
        v_percentage := 0;
    ELSE
        v_percentage := (v_days_passed::NUMERIC / v_total_days::NUMERIC) * 100;
    END IF;

    RETURN ROUND(v_percentage, 2);
END;
$$ LANGUAGE plpgsql STABLE;

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

    -- Weekly Breakdown
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
    v_target_fokus_detail JSONB;
    v_target_special_detail JSONB;
BEGIN
    -- Get time-gone percentage
    v_time_gone := public.get_time_gone_percentage(p_period_id);

    -- Get target omzet (All Type)
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

    -- Get target fokus total (fallback to detail map if total is zero)
    SELECT COALESCE(target_fokus_total, 0),
           COALESCE(target_fokus_detail, '{}'::jsonb),
           COALESCE(target_special_detail, '{}'::jsonb)
    INTO v_target_fokus, v_target_fokus_detail, v_target_special_detail
    FROM user_targets
    WHERE user_id = p_user_id AND period_id = p_period_id;

    v_target_fokus := COALESCE(v_target_fokus, 0);

    IF v_target_fokus <= 0 THEN
        v_target_fokus := COALESCE((
            SELECT SUM((value)::numeric)
            FROM jsonb_each_text(
                CASE
                    WHEN jsonb_typeof(v_target_fokus_detail) = 'object'
                         AND v_target_fokus_detail <> '{}'::jsonb
                        THEN v_target_fokus_detail
                    ELSE v_target_special_detail
                END
            )
        ), 0)::INT;
    END IF;

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

REFRESH MATERIALIZED VIEW v_target_dashboard;
