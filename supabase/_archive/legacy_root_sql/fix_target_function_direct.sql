-- Fix: Make get_target_dashboard query directly instead of from view
-- This bypasses materialized view refresh issues

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
) 
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_period_id UUID;
BEGIN
    -- Get period ID
    IF p_period_id IS NOT NULL THEN
        v_period_id := p_period_id;
    ELSE
        -- Get current period
        SELECT tp.id INTO v_period_id
        FROM target_periods tp
        WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
        AND tp.deleted_at IS NULL
        LIMIT 1;
    END IF;
    
    -- Return calculated data directly (bypass view)
    RETURN QUERY
    SELECT 
        tp.id as period_id,
        tp.period_name,
        tp.start_date,
        tp.end_date,
        ta.*
    FROM target_periods tp
    LEFT JOIN LATERAL calculate_target_achievement(p_user_id, tp.id) ta ON true
    WHERE tp.id = v_period_id
    AND tp.deleted_at IS NULL;
END;
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION get_target_dashboard(UUID, UUID) TO authenticated;

-- Test with Yohanis
SELECT 'TEST RESULT:' as info, * 
FROM get_target_dashboard('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);
