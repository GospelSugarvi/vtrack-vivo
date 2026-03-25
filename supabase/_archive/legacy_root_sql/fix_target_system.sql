-- Fix: Create functions in correct order
-- Run this if migration fails

-- ==========================================
-- STEP 1: Drop existing functions (if any)
-- ==========================================
DROP FUNCTION IF EXISTS get_target_dashboard(UUID, UUID);
DROP FUNCTION IF EXISTS calculate_target_achievement(UUID, UUID);
DROP FUNCTION IF EXISTS get_time_gone_percentage(UUID);
DROP MATERIALIZED VIEW IF EXISTS v_target_dashboard;

-- ==========================================
-- STEP 2: Create get_time_gone_percentage FIRST
-- ==========================================
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
    
    -- Calculate days passed (can't be negative or > total)
    v_days_passed := LEAST(CURRENT_DATE - v_start_date + 1, v_total_days);
    v_days_passed := GREATEST(v_days_passed, 0);
    
    -- Calculate percentage (avoid division by zero)
    IF v_total_days > 0 THEN
        v_percentage := (v_days_passed::NUMERIC / v_total_days::NUMERIC) * 100;
    ELSE
        v_percentage := 0;
    END IF;
    
    RETURN ROUND(v_percentage, 2);
END;
$$ LANGUAGE plpgsql STABLE;

-- Test it
SELECT 
    'Time-Gone Test' as test,
    period_name,
    start_date,
    end_date,
    get_time_gone_percentage(id) as time_gone_pct
FROM target_periods
WHERE deleted_at IS NULL
ORDER BY start_date DESC
LIMIT 3;

-- ==========================================
-- STEP 3: Create calculate_target_achievement
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
    v_time_gone NUMERIC;
    v_target_omzet NUMERIC;
    v_actual_omzet NUMERIC;
    v_achievement_omzet NUMERIC;
    v_target_fokus INTEGER;
    v_actual_fokus INTEGER;
    v_achievement_fokus NUMERIC;
    v_fokus_details JSONB;
BEGIN
    -- Get time-gone percentage (now function exists)
    v_time_gone := get_time_gone_percentage(p_period_id);
    
    -- Get target omzet (use target_sell_out for "All Type")
    SELECT COALESCE(ut.target_sell_out, ut.target_omzet, 0)
    INTO v_target_omzet
    FROM user_targets ut
    WHERE ut.user_id = p_user_id AND ut.period_id = p_period_id;
    
    v_target_omzet := COALESCE(v_target_omzet, 0);
    
    -- Get actual omzet
    SELECT COALESCE(dpm.total_omzet_real, 0)
    INTO v_actual_omzet
    FROM dashboard_performance_metrics dpm
    WHERE dpm.user_id = p_user_id AND dpm.period_id = p_period_id;
    
    v_actual_omzet := COALESCE(v_actual_omzet, 0);
    
    -- Calculate achievement
    IF v_target_omzet > 0 THEN
        v_achievement_omzet := (v_actual_omzet / v_target_omzet) * 100;
    ELSE
        v_achievement_omzet := 0;
    END IF;
    
    -- Get target fokus (total)
    SELECT COALESCE(ut.target_fokus, 0)
    INTO v_target_fokus
    FROM user_targets ut
    WHERE ut.user_id = p_user_id AND ut.period_id = p_period_id;
    
    v_target_fokus := COALESCE(v_target_fokus, 0);
    
    -- Get actual fokus
    SELECT COALESCE(dpm.total_units_focus, 0)
    INTO v_actual_fokus
    FROM dashboard_performance_metrics dpm
    WHERE dpm.user_id = p_user_id AND dpm.period_id = p_period_id;
    
    v_actual_fokus := COALESCE(v_actual_fokus, 0);
    
    -- Calculate fokus achievement
    IF v_target_fokus > 0 THEN
        v_achievement_fokus := (v_actual_fokus::NUMERIC / v_target_fokus::NUMERIC) * 100;
    ELSE
        v_achievement_fokus := 0;
    END IF;
    
    -- Get fokus details (simplified for now)
    v_fokus_details := '[]'::jsonb;
    
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
        CASE 
            WHEN v_achievement_omzet >= 100 THEN 'ACHIEVED'
            WHEN v_achievement_omzet >= v_time_gone THEN 'ON_TRACK'
            ELSE 'WARNING'
        END,
        CASE 
            WHEN v_achievement_fokus >= 100 THEN 'ACHIEVED'
            WHEN v_achievement_fokus >= v_time_gone THEN 'ON_TRACK'
            ELSE 'WARNING'
        END,
        (v_achievement_omzet < v_time_gone AND v_target_omzet > 0),
        (v_achievement_fokus < v_time_gone AND v_target_fokus > 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- Test it
SELECT * FROM calculate_target_achievement(
    (SELECT id FROM users WHERE role = 'promotor' LIMIT 1),
    (SELECT id FROM target_periods WHERE deleted_at IS NULL ORDER BY start_date DESC LIMIT 1)
);

-- ==========================================
-- STEP 4: Create get_target_dashboard
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
    IF p_period_id IS NOT NULL THEN
        RETURN QUERY
        SELECT 
            tp.id,
            tp.period_name,
            tp.start_date,
            tp.end_date,
            ta.*
        FROM target_periods tp
        LEFT JOIN LATERAL calculate_target_achievement(p_user_id, tp.id) ta ON true
        WHERE tp.id = p_period_id;
    ELSE
        RETURN QUERY
        SELECT 
            tp.id,
            tp.period_name,
            tp.start_date,
            tp.end_date,
            ta.*
        FROM target_periods tp
        LEFT JOIN LATERAL calculate_target_achievement(p_user_id, tp.id) ta ON true
        WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
        AND tp.deleted_at IS NULL
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- Test it
SELECT * FROM get_target_dashboard(
    (SELECT id FROM users WHERE role = 'promotor' LIMIT 1),
    NULL
);

-- ==========================================
-- STEP 5: Grant permissions
-- ==========================================
GRANT EXECUTE ON FUNCTION get_time_gone_percentage(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_target_achievement(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_target_dashboard(UUID, UUID) TO authenticated;

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Target Achievement System installed successfully!' as status;
