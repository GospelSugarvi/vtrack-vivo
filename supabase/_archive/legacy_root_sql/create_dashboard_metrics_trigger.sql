-- Create automatic trigger to update dashboard_performance_metrics
-- This will keep the aggregate table in sync with sales_sell_out
-- ==========================================

-- 1. Create function to update dashboard metrics
CREATE OR REPLACE FUNCTION update_dashboard_metrics()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_period_id UUID;
    v_transaction_date DATE;
BEGIN
    -- Get user_id and transaction_date from the affected row
    IF TG_OP = 'DELETE' THEN
        v_user_id := OLD.promotor_id;
        v_transaction_date := OLD.transaction_date;
    ELSE
        v_user_id := NEW.promotor_id;
        v_transaction_date := NEW.transaction_date;
    END IF;
    
    -- Get period_id based on transaction_date
    SELECT tp.id INTO v_period_id
    FROM target_periods tp
    WHERE v_transaction_date BETWEEN tp.start_date AND tp.end_date
    AND tp.deleted_at IS NULL
    LIMIT 1;
    
    -- Skip if no period found
    IF v_period_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    
    -- Recalculate metrics for this user and period
    INSERT INTO dashboard_performance_metrics (
        user_id,
        period_id,
        total_omzet_real,
        total_units_focus,
        last_updated
    )
    SELECT 
        v_user_id,
        v_period_id,
        COALESCE(SUM(so.price_at_transaction), 0) as total_omzet,
        COALESCE(COUNT(CASE WHEN p.is_fokus = true THEN 1 END), 0) as total_fokus,
        NOW()
    FROM sales_sell_out so
    JOIN product_variants pv ON so.variant_id = pv.id
    JOIN products p ON pv.product_id = p.id
    WHERE so.promotor_id = v_user_id
    AND so.transaction_date BETWEEN (SELECT start_date FROM target_periods WHERE id = v_period_id)
                                AND (SELECT end_date FROM target_periods WHERE id = v_period_id)
    AND so.deleted_at IS NULL
    
    ON CONFLICT (user_id, period_id) 
    DO UPDATE SET
        total_omzet_real = EXCLUDED.total_omzet_real,
        total_units_focus = EXCLUDED.total_units_focus,
        last_updated = NOW();
    
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 2. Create trigger on sales_sell_out table
DROP TRIGGER IF EXISTS trigger_update_dashboard_metrics ON sales_sell_out;

CREATE TRIGGER trigger_update_dashboard_metrics
    AFTER INSERT OR UPDATE OR DELETE ON sales_sell_out
    FOR EACH ROW
    EXECUTE FUNCTION update_dashboard_metrics();

-- 3. Populate existing data (backfill)
INSERT INTO dashboard_performance_metrics (
    user_id,
    period_id,
    total_omzet_real,
    total_units_focus,
    last_updated
)
SELECT 
    so.promotor_id,
    tp.id as period_id,
    COALESCE(SUM(so.price_at_transaction), 0) as total_omzet,
    COALESCE(COUNT(CASE WHEN p.is_fokus = true THEN 1 END), 0) as total_fokus,
    NOW()
FROM sales_sell_out so
JOIN product_variants pv ON so.variant_id = pv.id
JOIN products p ON pv.product_id = p.id
JOIN target_periods tp ON so.transaction_date BETWEEN tp.start_date AND tp.end_date
WHERE so.deleted_at IS NULL
AND tp.deleted_at IS NULL
GROUP BY so.promotor_id, tp.id

ON CONFLICT (user_id, period_id) 
DO UPDATE SET
    total_omzet_real = EXCLUDED.total_omzet_real,
    total_units_focus = EXCLUDED.total_units_focus,
    last_updated = NOW();

-- 4. Verify Yohanis data
SELECT 
    '=== YOHANIS METRICS AFTER TRIGGER ===' as status,
    u.full_name,
    tp.period_name,
    dpm.total_omzet_real,
    dpm.total_units_focus,
    dpm.last_updated
FROM dashboard_performance_metrics dpm
JOIN users u ON dpm.user_id = u.id
JOIN target_periods tp ON dpm.period_id = tp.id
WHERE dpm.user_id = 'a85b7470-47f8-481c-9dd0-d77ad851b4a7';

-- 5. Test target dashboard function
SELECT 
    '=== TARGET DASHBOARD FINAL TEST ===' as status,
    target_omzet,
    actual_omzet,
    achievement_omzet_pct,
    target_fokus_total,
    actual_fokus_total,
    achievement_fokus_pct
FROM get_target_dashboard('a85b7470-47f8-481c-9dd0-d77ad851b4a7', NULL);

SELECT '✅ Dashboard metrics trigger created and data populated!' as result;