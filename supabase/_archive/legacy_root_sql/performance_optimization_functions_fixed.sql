-- PERFORMANCE OPTIMIZATION - FUNCTION IMPROVEMENTS (FIXED)
-- Optimize database functions for better performance
-- ==========================================

-- 1. OPTIMIZED TARGET DASHBOARD FUNCTION (FIXED TYPE CASTING)
CREATE OR REPLACE FUNCTION get_target_dashboard_optimized(
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
    v_period_record RECORD;
    v_target_record RECORD;
    v_metrics_record RECORD;
    v_time_gone NUMERIC;
    v_achievement_omzet NUMERIC;
    v_achievement_fokus NUMERIC;
BEGIN
    -- Get period ID with single query
    IF p_period_id IS NOT NULL THEN
        v_period_id := p_period_id;
        SELECT tp.* INTO v_period_record
        FROM target_periods tp
        WHERE tp.id = v_period_id AND tp.deleted_at IS NULL;
    ELSE
        SELECT tp.* INTO v_period_record
        FROM target_periods tp
        WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
        AND tp.deleted_at IS NULL
        LIMIT 1;
        v_period_id := v_period_record.id;
    END IF;
    
    -- Return empty if no period found
    IF v_period_record.id IS NULL THEN
        RETURN;
    END IF;
    
    -- Get target data
    SELECT 
        COALESCE(ut.target_omzet, 0) as target_omzet,
        COALESCE(ut.target_fokus_total, 0) as target_fokus_total
    INTO v_target_record
    FROM user_targets ut
    WHERE ut.user_id = p_user_id AND ut.period_id = v_period_id;
    
    -- Get metrics data (from aggregate table)
    SELECT 
        COALESCE(dpm.total_omzet_real, 0) as actual_omzet,
        COALESCE(dpm.total_units_focus, 0) as actual_fokus
    INTO v_metrics_record
    FROM dashboard_performance_metrics dpm
    WHERE dpm.user_id = p_user_id AND dpm.period_id = v_period_id;
    
    -- Calculate time gone percentage (FIXED TYPE CASTING)
    v_time_gone := CASE 
        WHEN v_period_record.end_date <= CURRENT_DATE THEN 100.0
        WHEN v_period_record.start_date > CURRENT_DATE THEN 0.0
        ELSE ROUND(
            (EXTRACT(EPOCH FROM (CURRENT_DATE::timestamp - v_period_record.start_date::timestamp)) / 
             EXTRACT(EPOCH FROM (v_period_record.end_date::timestamp - v_period_record.start_date::timestamp))) * 100, 2
        )
    END;
    
    -- Calculate achievements
    v_achievement_omzet := CASE 
        WHEN COALESCE(v_target_record.target_omzet, 0) > 0 
        THEN ROUND((COALESCE(v_metrics_record.actual_omzet, 0) / v_target_record.target_omzet) * 100, 2)
        ELSE 0 
    END;
    
    v_achievement_fokus := CASE 
        WHEN COALESCE(v_target_record.target_fokus_total, 0) > 0 
        THEN ROUND((COALESCE(v_metrics_record.actual_fokus, 0)::NUMERIC / v_target_record.target_fokus_total) * 100, 2)
        ELSE 0 
    END;
    
    -- Return optimized result
    RETURN QUERY SELECT
        v_period_record.id,
        v_period_record.period_name,
        v_period_record.start_date,
        v_period_record.end_date,
        COALESCE(v_target_record.target_omzet, 0),
        COALESCE(v_metrics_record.actual_omzet, 0),
        v_achievement_omzet,
        COALESCE(v_target_record.target_fokus_total, 0),
        COALESCE(v_metrics_record.actual_fokus, 0),
        v_achievement_fokus,
        '[]'::jsonb, -- Fokus details can be loaded separately if needed
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
        (v_achievement_omzet < v_time_gone AND COALESCE(v_target_record.target_omzet, 0) > 0),
        (v_achievement_fokus < v_time_gone AND COALESCE(v_target_record.target_fokus_total, 0) > 0);
END;
$$;

-- 2. OPTIMIZED DASHBOARD METRICS UPDATE FUNCTION
CREATE OR REPLACE FUNCTION update_dashboard_metrics_optimized()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_period_id UUID;
    v_transaction_date DATE;
    v_total_omzet NUMERIC;
    v_total_fokus INTEGER;
BEGIN
    -- Get affected user and date
    IF TG_OP = 'DELETE' THEN
        v_user_id := OLD.promotor_id;
        v_transaction_date := OLD.transaction_date;
    ELSE
        v_user_id := NEW.promotor_id;
        v_transaction_date := NEW.transaction_date;
    END IF;
    
    -- Get period_id using optimized query
    SELECT tp.id INTO v_period_id
    FROM target_periods tp
    WHERE v_transaction_date BETWEEN tp.start_date AND tp.end_date
    AND tp.deleted_at IS NULL
    LIMIT 1;
    
    -- Skip if no period found
    IF v_period_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    
    -- Calculate metrics with single query
    SELECT 
        COALESCE(SUM(so.price_at_transaction), 0),
        COALESCE(COUNT(CASE WHEN p.is_fokus = true THEN 1 END), 0)
    INTO v_total_omzet, v_total_fokus
    FROM sales_sell_out so
    JOIN product_variants pv ON so.variant_id = pv.id
    JOIN products p ON pv.product_id = p.id
    WHERE so.promotor_id = v_user_id
    AND so.transaction_date BETWEEN (SELECT start_date FROM target_periods WHERE id = v_period_id)
                                AND (SELECT end_date FROM target_periods WHERE id = v_period_id)
    AND so.deleted_at IS NULL;
    
    -- Upsert metrics
    INSERT INTO dashboard_performance_metrics (
        user_id, period_id, total_omzet_real, total_units_focus, last_updated
    ) VALUES (
        v_user_id, v_period_id, v_total_omzet, v_total_fokus, NOW()
    )
    ON CONFLICT (user_id, period_id) 
    DO UPDATE SET
        total_omzet_real = EXCLUDED.total_omzet_real,
        total_units_focus = EXCLUDED.total_units_focus,
        last_updated = NOW();
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 3. BATCH METRICS RECALCULATION FUNCTION
CREATE OR REPLACE FUNCTION recalculate_all_dashboard_metrics()
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_processed INTEGER := 0;
    v_user_period RECORD;
BEGIN
    -- Truncate and rebuild all metrics
    TRUNCATE dashboard_performance_metrics;
    
    -- Recalculate for all user-period combinations
    FOR v_user_period IN
        SELECT DISTINCT 
            so.promotor_id as user_id,
            tp.id as period_id,
            tp.start_date,
            tp.end_date
        FROM sales_sell_out so
        JOIN target_periods tp ON so.transaction_date BETWEEN tp.start_date AND tp.end_date
        WHERE so.deleted_at IS NULL AND tp.deleted_at IS NULL
    LOOP
        INSERT INTO dashboard_performance_metrics (
            user_id, period_id, total_omzet_real, total_units_focus, last_updated
        )
        SELECT 
            v_user_period.user_id,
            v_user_period.period_id,
            COALESCE(SUM(so.price_at_transaction), 0),
            COALESCE(COUNT(CASE WHEN p.is_fokus = true THEN 1 END), 0),
            NOW()
        FROM sales_sell_out so
        JOIN product_variants pv ON so.variant_id = pv.id
        JOIN products p ON pv.product_id = p.id
        WHERE so.promotor_id = v_user_period.user_id
        AND so.transaction_date BETWEEN v_user_period.start_date AND v_user_period.end_date
        AND so.deleted_at IS NULL;
        
        v_processed := v_processed + 1;
    END LOOP;
    
    RETURN format('✅ Recalculated metrics for %s user-period combinations', v_processed);
END;
$$;

-- 4. GRANT PERMISSIONS
GRANT EXECUTE ON FUNCTION get_target_dashboard_optimized(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION recalculate_all_dashboard_metrics() TO authenticated;

-- 5. PERFORMANCE TEST
EXPLAIN (ANALYZE, BUFFERS) 
SELECT * FROM get_target_dashboard_optimized('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);

SELECT '✅ Function optimizations complete!' as result;