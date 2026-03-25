-- ==========================================
-- TARGET DASHBOARD SETUP - STEP 1
-- Create helper function first
-- ==========================================

CREATE OR REPLACE FUNCTION get_time_gone_percentage(p_period_id UUID)
RETURNS NUMERIC 
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
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
$$;

-- Grant permission
GRANT EXECUTE ON FUNCTION get_time_gone_percentage(UUID) TO authenticated;

-- Success message
SELECT '✅ Step 1 complete: get_time_gone_percentage function created' as status;
