-- Unify team bonus metrics across promotor, sator, and spv.
-- Source of truth:
--   - sales_sell_out for transaction/revenue/unit counts
--   - sales_bonus_events for realized bonus
--   - fallback to sales_sell_out.estimated_bonus when ledger is still zero

CREATE OR REPLACE FUNCTION public.resolve_effective_bonus_amount(
  p_sales_sell_out_id UUID,
  p_estimated_bonus NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    CASE
      WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC
      WHEN COALESCE(p_estimated_bonus, 0) > 0 THEN COALESCE(p_estimated_bonus, 0)::NUMERIC
      ELSE 0::NUMERIC
    END
  FROM public.sales_bonus_events sbe
  WHERE sbe.sales_sell_out_id = p_sales_sell_out_id
$$;

CREATE OR REPLACE FUNCTION public.recalculate_dashboard_metrics_for_user_period(
  p_user_id UUID,
  p_period_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.dashboard_performance_metrics
  WHERE user_id = p_user_id
    AND period_id = p_period_id;

  INSERT INTO public.dashboard_performance_metrics (
    user_id,
    period_id,
    total_omzet_real,
    total_units_focus,
    total_units_sold,
    estimated_bonus_total,
    last_updated
  )
  SELECT
    p_user_id,
    p_period_id,
    COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
    COALESCE(COUNT(CASE WHEN p.is_focus = true OR p.is_fokus = true THEN 1 END), 0) AS total_units_focus,
    COALESCE(COUNT(*), 0) AS total_units_sold,
    COALESCE(SUM(public.resolve_effective_bonus_amount(so.id, so.estimated_bonus)), 0) AS estimated_bonus_total,
    NOW()
  FROM public.sales_sell_out so
  JOIN public.target_periods tp
    ON tp.id = p_period_id
   AND so.transaction_date BETWEEN tp.start_date AND tp.end_date
   AND tp.deleted_at IS NULL
  JOIN public.product_variants pv ON pv.id = so.variant_id
  JOIN public.products p ON p.id = pv.product_id
  WHERE so.promotor_id = p_user_id
    AND so.deleted_at IS NULL
    AND COALESCE(so.is_chip_sale, false) = false;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_dashboard_metrics()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_period_id UUID;
  v_transaction_date DATE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_user_id := OLD.promotor_id;
    v_transaction_date := OLD.transaction_date;
  ELSE
    v_user_id := NEW.promotor_id;
    v_transaction_date := NEW.transaction_date;
  END IF;

  SELECT tp.id
  INTO v_period_id
  FROM public.target_periods tp
  WHERE v_transaction_date BETWEEN tp.start_date AND tp.end_date
    AND tp.deleted_at IS NULL
  LIMIT 1;

  IF v_user_id IS NOT NULL AND v_period_id IS NOT NULL THEN
    PERFORM public.recalculate_dashboard_metrics_for_user_period(v_user_id, v_period_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_dashboard_metrics_from_bonus_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_sales_sell_out_id UUID;
  v_user_id UUID;
  v_transaction_date DATE;
  v_period_id UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_sales_sell_out_id := OLD.sales_sell_out_id;
  ELSE
    v_sales_sell_out_id := NEW.sales_sell_out_id;
  END IF;

  SELECT so.promotor_id, so.transaction_date
  INTO v_user_id, v_transaction_date
  FROM public.sales_sell_out so
  WHERE so.id = v_sales_sell_out_id;

  IF v_user_id IS NULL OR v_transaction_date IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT tp.id
  INTO v_period_id
  FROM public.target_periods tp
  WHERE v_transaction_date BETWEEN tp.start_date AND tp.end_date
    AND tp.deleted_at IS NULL
  LIMIT 1;

  IF v_period_id IS NOT NULL THEN
    PERFORM public.recalculate_dashboard_metrics_for_user_period(v_user_id, v_period_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_update_dashboard_metrics ON public.sales_sell_out;
CREATE TRIGGER trg_update_dashboard_metrics
AFTER INSERT OR UPDATE OR DELETE ON public.sales_sell_out
FOR EACH ROW
EXECUTE FUNCTION public.update_dashboard_metrics();

DROP TRIGGER IF EXISTS trg_update_dashboard_metrics_from_bonus_event ON public.sales_bonus_events;
CREATE TRIGGER trg_update_dashboard_metrics_from_bonus_event
AFTER INSERT OR UPDATE OR DELETE ON public.sales_bonus_events
FOR EACH ROW
EXECUTE FUNCTION public.update_dashboard_metrics_from_bonus_event();

CREATE OR REPLACE FUNCTION public.refresh_dashboard_performance_metrics(
  p_period_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_period_id IS NULL THEN
    DELETE FROM public.dashboard_performance_metrics;

    INSERT INTO public.dashboard_performance_metrics (
      user_id,
      period_id,
      total_omzet_real,
      total_units_focus,
      total_units_sold,
      estimated_bonus_total,
      last_updated
    )
    SELECT
      so.promotor_id,
      tp.id,
      COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
      COALESCE(COUNT(CASE WHEN p.is_focus = true OR p.is_fokus = true THEN 1 END), 0) AS total_units_focus,
      COALESCE(COUNT(*), 0) AS total_units_sold,
      COALESCE(SUM(public.resolve_effective_bonus_amount(so.id, so.estimated_bonus)), 0) AS estimated_bonus_total,
      NOW()
    FROM public.sales_sell_out so
    JOIN public.target_periods tp
      ON so.transaction_date BETWEEN tp.start_date AND tp.end_date
     AND tp.deleted_at IS NULL
    JOIN public.product_variants pv ON pv.id = so.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE so.deleted_at IS NULL
      AND COALESCE(so.is_chip_sale, false) = false
    GROUP BY so.promotor_id, tp.id;
  ELSE
    DELETE FROM public.dashboard_performance_metrics
    WHERE period_id = p_period_id;

    INSERT INTO public.dashboard_performance_metrics (
      user_id,
      period_id,
      total_omzet_real,
      total_units_focus,
      total_units_sold,
      estimated_bonus_total,
      last_updated
    )
    SELECT
      so.promotor_id,
      p_period_id,
      COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
      COALESCE(COUNT(CASE WHEN p.is_focus = true OR p.is_fokus = true THEN 1 END), 0) AS total_units_focus,
      COALESCE(COUNT(*), 0) AS total_units_sold,
      COALESCE(SUM(public.resolve_effective_bonus_amount(so.id, so.estimated_bonus)), 0) AS estimated_bonus_total,
      NOW()
    FROM public.sales_sell_out so
    JOIN public.target_periods tp
      ON tp.id = p_period_id
     AND so.transaction_date BETWEEN tp.start_date AND tp.end_date
     AND tp.deleted_at IS NULL
    JOIN public.product_variants pv ON pv.id = so.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE so.deleted_at IS NULL
      AND COALESCE(so.is_chip_sale, false) = false
    GROUP BY so.promotor_id;
  END IF;
END;
$$;

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
  v_total_bonus NUMERIC;
BEGIN
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM public.target_periods
  WHERE start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE
  LIMIT 1;

  SELECT COALESCE(target_sell_out, 0), COALESCE(target_fokus, 0), COALESCE(target_sell_in, 0)
  INTO v_target_sellout, v_target_fokus, v_target_sellin
  FROM public.user_targets
  WHERE user_id = p_sator_id AND period_id = v_period_id;

  SELECT
    COALESCE(SUM(dpm.total_omzet_real), 0),
    COALESCE(SUM(dpm.total_units_focus), 0),
    COALESCE(SUM(dpm.estimated_bonus_total), 0)
  INTO v_actual_sellout, v_actual_fokus, v_total_bonus
  FROM public.dashboard_performance_metrics dpm
  WHERE dpm.period_id = v_period_id
    AND dpm.user_id IN (
      SELECT promotor_id
      FROM public.hierarchy_sator_promotor
      WHERE sator_id = p_sator_id AND active = true
    );

  SELECT COALESCE(SUM(total_value), 0)
  INTO v_actual_sellin
  FROM public.sales_sell_in
  WHERE sator_id = p_sator_id
    AND transaction_date BETWEEN v_start AND v_end
    AND deleted_at IS NULL;

  v_ma_score := COALESCE(public.get_sator_kpi_ma(p_sator_id, v_start), 0);

  v_sellout_score := CASE WHEN v_target_sellout > 0 THEN (v_actual_sellout * 100 / v_target_sellout) ELSE 0 END;
  v_fokus_score := CASE WHEN v_target_fokus > 0 THEN (v_actual_fokus * 100 / v_target_fokus) ELSE 0 END;
  v_sellin_score := CASE WHEN v_target_sellin > 0 THEN (v_actual_sellin * 100 / v_target_sellin) ELSE 0 END;

  v_total_score := (
    COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'sator' AND kpi_name ILIKE '%Sell Out All%'), 0) * v_sellout_score
    + COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'sator' AND kpi_name ILIKE '%Sell Out Fokus%'), 0) * v_fokus_score
    + COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'sator' AND kpi_name ILIKE '%Sell In%'), 0) * v_sellin_score
    + COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'sator' AND kpi_name ILIKE '%KPI MA%'), 0) * v_ma_score
  ) / 100;

  v_result := json_build_object(
    'sell_out_all_score', v_sellout_score,
    'sell_out_fokus_score', v_fokus_score,
    'sell_in_score', v_sellin_score,
    'kpi_ma_score', v_ma_score,
    'total_score', v_total_score,
    'total_bonus', COALESCE(v_total_bonus, 0)
  );

  RETURN v_result;
END;
$$;

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
  v_total_bonus NUMERIC;
BEGIN
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM public.target_periods
  WHERE start_date <= CURRENT_DATE AND end_date >= CURRENT_DATE
  LIMIT 1;

  SELECT COALESCE(target_sell_out, 0), COALESCE(target_fokus, 0), COALESCE(target_sell_in, 0)
  INTO v_target_sellout, v_target_fokus, v_target_sellin
  FROM public.user_targets
  WHERE user_id = p_spv_id AND period_id = v_period_id;

  IF v_target_sellout = 0 OR v_target_fokus = 0 THEN
    SELECT COALESCE(SUM(ut.target_omzet), 0), COALESCE(SUM(ut.target_fokus_total), 0)
    INTO v_target_sellout, v_target_fokus
    FROM public.user_targets ut
    WHERE ut.period_id = v_period_id
      AND ut.user_id IN (
        SELECT hsp.promotor_id
        FROM public.hierarchy_sator_promotor hsp
        JOIN public.hierarchy_spv_sator hss
          ON hss.sator_id = hsp.sator_id
         AND hss.active = true
        WHERE hss.spv_id = p_spv_id
          AND hsp.active = true
      );
  END IF;

  SELECT
    COALESCE(SUM(dpm.total_omzet_real), 0),
    COALESCE(SUM(dpm.total_units_focus), 0),
    COALESCE(SUM(dpm.estimated_bonus_total), 0)
  INTO v_actual_sellout, v_actual_fokus, v_total_bonus
  FROM public.dashboard_performance_metrics dpm
  WHERE dpm.period_id = v_period_id
    AND dpm.user_id IN (
      SELECT hsp.promotor_id
      FROM public.hierarchy_sator_promotor hsp
      JOIN public.hierarchy_spv_sator hss
        ON hss.sator_id = hsp.sator_id
       AND hss.active = true
      WHERE hss.spv_id = p_spv_id
        AND hsp.active = true
    );

  SELECT COALESCE(SUM(si.total_value), 0)
  INTO v_actual_sellin
  FROM public.sales_sell_in si
  WHERE si.transaction_date BETWEEN v_start AND v_end
    AND si.deleted_at IS NULL
    AND si.sator_id IN (
      SELECT sator_id
      FROM public.hierarchy_spv_sator
      WHERE spv_id = p_spv_id AND active = true
    );

  SELECT COALESCE(AVG(score), 0)
  INTO v_ma_score
  FROM public.kpi_ma_scores
  WHERE period_date = v_start
    AND sator_id IN (
      SELECT sator_id
      FROM public.hierarchy_spv_sator
      WHERE spv_id = p_spv_id AND active = true
    );

  v_sellout_score := CASE WHEN v_target_sellout > 0 THEN (v_actual_sellout * 100 / v_target_sellout) ELSE 0 END;
  v_fokus_score := CASE WHEN v_target_fokus > 0 THEN (v_actual_fokus * 100 / v_target_fokus) ELSE 0 END;
  v_sellin_score := CASE WHEN v_target_sellin > 0 THEN (v_actual_sellin * 100 / v_target_sellin) ELSE 0 END;

  v_total_score := (
    COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'spv' AND kpi_name ILIKE '%Sell Out All%'), 0) * v_sellout_score
    + COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'spv' AND kpi_name ILIKE '%Sell Out Produk Fokus%'), 0) * v_fokus_score
    + COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'spv' AND kpi_name ILIKE '%Sell In%'), 0) * v_sellin_score
    + COALESCE((SELECT weight FROM public.kpi_settings WHERE role = 'spv' AND kpi_name ILIKE '%KPI MA%'), 0) * v_ma_score
  ) / 100;

  v_result := json_build_object(
    'sell_out_all_score', v_sellout_score,
    'sell_out_fokus_score', v_fokus_score,
    'sell_in_score', v_sellin_score,
    'kpi_ma_score', v_ma_score,
    'total_score', v_total_score,
    'total_bonus', COALESCE(v_total_bonus, 0)
  );

  RETURN v_result;
END;
$$;

SELECT public.refresh_dashboard_performance_metrics(NULL);
