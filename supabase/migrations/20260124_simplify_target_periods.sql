-- Simplify Target Periods System
-- Change from free-text "period_name" to structured MONTH + YEAR

-- ==========================================
-- STEP 1: Add month and year columns
-- ==========================================
ALTER TABLE target_periods
ADD COLUMN IF NOT EXISTS target_month INTEGER,
ADD COLUMN IF NOT EXISTS target_year INTEGER;

-- ==========================================
-- STEP 2: Create unique constraint
-- ==========================================
-- Drop old constraint if exists
ALTER TABLE target_periods DROP CONSTRAINT IF EXISTS unique_month_year;

-- Add new constraint: one period per month-year
ALTER TABLE target_periods
ADD CONSTRAINT unique_month_year UNIQUE (target_month, target_year);

-- ==========================================
-- STEP 3: Migrate existing data
-- ==========================================
-- Try to parse existing period_name to extract month/year
-- Example: "Januari 2026" -> month=1, year=2026

UPDATE target_periods
SET 
    target_month = EXTRACT(MONTH FROM start_date),
    target_year = EXTRACT(YEAR FROM start_date)
WHERE target_month IS NULL;

-- ==========================================
-- STEP 4: Create helper function to get/create period
-- ==========================================
CREATE OR REPLACE FUNCTION get_or_create_target_period(
    p_month INTEGER,
    p_year INTEGER
)
RETURNS UUID AS $$
DECLARE
    v_period_id UUID;
    v_start_date DATE;
    v_end_date DATE;
    v_period_name TEXT;
    v_month_names TEXT[] := ARRAY[
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
BEGIN
    -- Check if period exists
    SELECT id INTO v_period_id
    FROM target_periods
    WHERE target_month = p_month
    AND target_year = p_year
    AND deleted_at IS NULL;
    
    IF v_period_id IS NOT NULL THEN
        RETURN v_period_id;
    END IF;
    
    -- Create new period
    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    v_period_name := v_month_names[p_month] || ' ' || p_year;
    
    INSERT INTO target_periods (
        period_name,
        start_date,
        end_date,
        target_month,
        target_year,
        status
    ) VALUES (
        v_period_name,
        v_start_date,
        v_end_date,
        p_month,
        p_year,
        'active'
    )
    RETURNING id INTO v_period_id;
    
    RETURN v_period_id;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- STEP 5: Create function to get current period
-- ==========================================
CREATE OR REPLACE FUNCTION get_current_target_period()
RETURNS UUID AS $$
DECLARE
    v_current_month INTEGER;
    v_current_year INTEGER;
BEGIN
    v_current_month := EXTRACT(MONTH FROM CURRENT_DATE);
    v_current_year := EXTRACT(YEAR FROM CURRENT_DATE);
    
    RETURN get_or_create_target_period(v_current_month, v_current_year);
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- STEP 6: Update get_target_dashboard to use current month
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
        -- Get current month's period
        RETURN QUERY
        SELECT 
            tp.id,
            tp.period_name,
            tp.start_date,
            tp.end_date,
            ta.*
        FROM target_periods tp
        LEFT JOIN LATERAL calculate_target_achievement(p_user_id, tp.id) ta ON true
        WHERE tp.target_month = EXTRACT(MONTH FROM CURRENT_DATE)
        AND tp.target_year = EXTRACT(YEAR FROM CURRENT_DATE)
        AND tp.deleted_at IS NULL
        LIMIT 1;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- STEP 7: Grant permissions
-- ==========================================
GRANT EXECUTE ON FUNCTION get_or_create_target_period(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_current_target_period() TO authenticated;

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Target period system simplified!' as status;
SELECT 'Now using MONTH + YEAR instead of free-text period names' as info;
