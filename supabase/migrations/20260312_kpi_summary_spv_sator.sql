-- Migration: 20260312_kpi_summary_spv_sator.sql
-- Compute KPI summary for SATOR (live) and SPV

-- 1) Update SATOR KPI summary to compute live from targets & actuals
CREATE OR REPLACE FUNCTION public.get_sator_kpi_summary(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_period_id UUID;
  v_start DATE;
  v_end DATE;
  v_target_sellout NUMERIC;
  v_target_fokus NUMERIC;
  v_target_sellin NUMERIC;
  v_actual_sellout NUMERIC;
  v_actual_fokus NUMERIC;
  v_actual_sellin NUMERIC;
  v_ma_score NUMERIC;
  v_sellout_score NUMERIC;
  v_fokus_score NUMERIC;
  v_sellin_score NUMERIC;
  v_total_score NUMERIC;
BEGIN
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM target_periods
  WHERE start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
  LIMIT 1;

  SELECT COALESCE(target_sell_out, 0), COALESCE(target_fokus, 0), COALESCE(target_sell_in, 0)
  INTO v_target_sellout, v_target_fokus, v_target_sellin
  FROM user_targets
  WHERE user_id = p_sator_id AND period_id = v_period_id;

  -- Actual sell-out (team promotors)
  SELECT COALESCE(SUM(dpm.total_omzet_real), 0), COALESCE(SUM(dpm.total_units_focus), 0)
  INTO v_actual_sellout, v_actual_fokus
  FROM dashboard_performance_metrics dpm
  WHERE dpm.period_id = v_period_id
    AND dpm.user_id IN (
      SELECT promotor_id FROM hierarchy_sator_promotor
      WHERE sator_id = p_sator_id AND active = true
    );

  -- Actual sell-in (SATOR)
  SELECT COALESCE(SUM(total_value), 0)
  INTO v_actual_sellin
  FROM sales_sell_in
  WHERE sator_id = p_sator_id
    AND transaction_date BETWEEN v_start AND v_end
    AND deleted_at IS NULL;

  v_ma_score := COALESCE(get_sator_kpi_ma(p_sator_id, v_start), 0);

  v_sellout_score := CASE WHEN v_target_sellout > 0 THEN (v_actual_sellout * 100 / v_target_sellout) ELSE 0 END;
  v_fokus_score := CASE WHEN v_target_fokus > 0 THEN (v_actual_fokus * 100 / v_target_fokus) ELSE 0 END;
  v_sellin_score := CASE WHEN v_target_sellin > 0 THEN (v_actual_sellin * 100 / v_target_sellin) ELSE 0 END;

  v_total_score := (
    COALESCE((SELECT weight FROM kpi_settings WHERE role='sator' AND kpi_name ILIKE '%Sell Out All%'), 0) * v_sellout_score
    + COALESCE((SELECT weight FROM kpi_settings WHERE role='sator' AND kpi_name ILIKE '%Sell Out Fokus%'), 0) * v_fokus_score
    + COALESCE((SELECT weight FROM kpi_settings WHERE role='sator' AND kpi_name ILIKE '%Sell In%'), 0) * v_sellin_score
  ) / 100;

  v_result := json_build_object(
    'sell_out_all_score', v_sellout_score,
    'sell_out_fokus_score', v_fokus_score,
    'sell_in_score', v_sellin_score,
    'kpi_ma_score', v_ma_score,
    'total_score', v_total_score,
    'total_bonus', 0
  );

  RETURN v_result;
END;
$$;

-- 2) SPV KPI summary
CREATE OR REPLACE FUNCTION public.get_spv_kpi_summary(p_spv_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_period_id UUID;
  v_start DATE;
  v_end DATE;
  v_target_sellout NUMERIC;
  v_target_fokus NUMERIC;
  v_target_sellin NUMERIC;
  v_actual_sellout NUMERIC;
  v_actual_fokus NUMERIC;
  v_actual_sellin NUMERIC;
  v_ma_score NUMERIC;
  v_sellout_score NUMERIC;
  v_fokus_score NUMERIC;
  v_sellin_score NUMERIC;
  v_total_score NUMERIC;
BEGIN
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM target_periods
  WHERE start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
  LIMIT 1;

  SELECT COALESCE(target_sell_out, 0), COALESCE(target_fokus, 0), COALESCE(target_sell_in, 0)
  INTO v_target_sellout, v_target_fokus, v_target_sellin
  FROM user_targets
  WHERE user_id = p_spv_id AND period_id = v_period_id;

  -- Fallback target from team promotors if SPV target is 0
  IF v_target_sellout = 0 OR v_target_fokus = 0 THEN
    SELECT COALESCE(SUM(ut.target_omzet), 0), COALESCE(SUM(ut.target_fokus_total), 0)
    INTO v_target_sellout, v_target_fokus
    FROM user_targets ut
    WHERE ut.period_id = v_period_id
      AND ut.user_id IN (
        SELECT promotor_id
        FROM hierarchy_sator_promotor hsp
        JOIN hierarchy_spv_sator hss ON hss.sator_id = hsp.sator_id AND hss.active = true
        WHERE hss.spv_id = p_spv_id AND hsp.active = true
      );
  END IF;

  -- Actual sell-out (team promotors)
  SELECT COALESCE(SUM(dpm.total_omzet_real), 0), COALESCE(SUM(dpm.total_units_focus), 0)
  INTO v_actual_sellout, v_actual_fokus
  FROM dashboard_performance_metrics dpm
  WHERE dpm.period_id = v_period_id
    AND dpm.user_id IN (
      SELECT promotor_id
      FROM hierarchy_sator_promotor hsp
      JOIN hierarchy_spv_sator hss ON hss.sator_id = hsp.sator_id AND hss.active = true
      WHERE hss.spv_id = p_spv_id AND hsp.active = true
    );

  -- Actual sell-in (team sators)
  SELECT COALESCE(SUM(si.total_value), 0)
  INTO v_actual_sellin
  FROM sales_sell_in si
  WHERE si.transaction_date BETWEEN v_start AND v_end
    AND si.deleted_at IS NULL
    AND si.sator_id IN (
      SELECT sator_id
      FROM hierarchy_spv_sator
      WHERE spv_id = p_spv_id AND active = true
    );

  -- KPI MA = average of sator MA scores
  SELECT COALESCE(AVG(score), 0)
  INTO v_ma_score
  FROM kpi_ma_scores
  WHERE period_date = v_start
    AND sator_id IN (
      SELECT sator_id
      FROM hierarchy_spv_sator
      WHERE spv_id = p_spv_id AND active = true
    );

  v_sellout_score := CASE WHEN v_target_sellout > 0 THEN (v_actual_sellout * 100 / v_target_sellout) ELSE 0 END;
  v_fokus_score := CASE WHEN v_target_fokus > 0 THEN (v_actual_fokus * 100 / v_target_fokus) ELSE 0 END;
  v_sellin_score := CASE WHEN v_target_sellin > 0 THEN (v_actual_sellin * 100 / v_target_sellin) ELSE 0 END;

  v_total_score := (
    COALESCE((SELECT weight FROM kpi_settings WHERE role='spv' AND kpi_name ILIKE '%Sell Out All%'), 0) * v_sellout_score
    + COALESCE((SELECT weight FROM kpi_settings WHERE role='spv' AND kpi_name ILIKE '%Sell Out Produk Fokus%'), 0) * v_fokus_score
    + COALESCE((SELECT weight FROM kpi_settings WHERE role='spv' AND kpi_name ILIKE '%Sell In%'), 0) * v_sellin_score
    + COALESCE((SELECT weight FROM kpi_settings WHERE role='spv' AND kpi_name ILIKE '%KPI MA%'), 0) * v_ma_score
  ) / 100;

  v_result := json_build_object(
    'sell_out_all_score', v_sellout_score,
    'sell_out_fokus_score', v_fokus_score,
    'sell_in_score', v_sellin_score,
    'kpi_ma_score', v_ma_score,
    'total_score', v_total_score,
    'total_bonus', 0
  );

  RETURN v_result;
END;
$$;
