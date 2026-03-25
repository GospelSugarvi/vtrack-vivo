-- Migration: 20260313_sator_home_summary.sql
-- Purpose: Provide SATOR home summary data (monthly, daily, weekly, agenda)

CREATE OR REPLACE FUNCTION public.get_sator_home_summary(
  p_sator_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result json;
  v_period_id uuid;
  v_start date;
  v_end date;
  v_days int := 0;
  v_day_index int := 0;

  v_store_count int := 0;
  v_promotor_count int := 0;

  v_target_sellout numeric := 0;
  v_target_fokus numeric := 0;
  v_target_sellin numeric := 0;

  v_actual_sellout numeric := 0;
  v_actual_fokus numeric := 0;
  v_actual_sellin numeric := 0;

  v_daily_target_sellout numeric := 0;
  v_daily_target_fokus numeric := 0;
  v_daily_target_sellin numeric := 0;

  v_today_sellout numeric := 0;
  v_today_fokus numeric := 0;
  v_today_sellin numeric := 0;

  v_weekly json := '[]'::json;
  v_agenda json := '[]'::json;
BEGIN
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM target_periods
  WHERE start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE
  LIMIT 1;

  IF v_period_id IS NULL THEN
    RETURN json_build_object('period', NULL);
  END IF;

  v_days := (v_end - v_start + 1);
  v_day_index := (CURRENT_DATE - v_start + 1);

  SELECT COUNT(*)
  INTO v_store_count
  FROM assignments_sator_store
  WHERE sator_id = p_sator_id AND active = true;

  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COUNT(*)
  INTO v_promotor_count
  FROM promotor_ids;

  SELECT
    COALESCE(target_sell_out, 0),
    COALESCE(target_fokus, 0),
    COALESCE(target_sell_in, 0)
  INTO v_target_sellout, v_target_fokus, v_target_sellin
  FROM user_targets
  WHERE user_id = p_sator_id AND period_id = v_period_id;

  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT
    COALESCE(SUM(dpm.total_omzet_real), 0),
    COALESCE(SUM(dpm.total_units_focus), 0)
  INTO v_actual_sellout, v_actual_fokus
  FROM dashboard_performance_metrics dpm
  WHERE dpm.period_id = v_period_id
    AND dpm.user_id IN (SELECT promotor_id FROM promotor_ids);

  SELECT COALESCE(SUM(total_value), 0)
  INTO v_actual_sellin
  FROM sales_sell_in
  WHERE sator_id = p_sator_id
    AND transaction_date BETWEEN v_start AND v_end
    AND deleted_at IS NULL;

  IF v_days > 0 THEN
    v_daily_target_sellout := v_target_sellout / v_days;
    v_daily_target_fokus := v_target_fokus / v_days;
    v_daily_target_sellin := v_target_sellin / v_days;
  END IF;

  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT
    COALESCE(SUM(s.price_at_transaction), 0),
    COALESCE(COUNT(CASE WHEN p.is_focus = true THEN 1 END), 0)
  INTO v_today_sellout, v_today_fokus
  FROM sales_sell_out s
  JOIN promotor_ids pi ON pi.promotor_id = s.promotor_id
  JOIN product_variants pv ON pv.id = s.variant_id
  JOIN products p ON p.id = pv.product_id
  WHERE s.transaction_date = CURRENT_DATE
    AND s.deleted_at IS NULL
    AND COALESCE(s.is_chip_sale, false) = false;

  SELECT COALESCE(SUM(total_value), 0)
  INTO v_today_sellin
  FROM sales_sell_in
  WHERE sator_id = p_sator_id
    AND transaction_date = CURRENT_DATE
    AND deleted_at IS NULL;

  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  weekly AS (
    SELECT
      (FLOOR((s.transaction_date - v_start) / 7) + 1)::int AS week_index,
      COALESCE(SUM(s.price_at_transaction), 0) AS omzet,
      COALESCE(COUNT(CASE WHEN p.is_focus = true THEN 1 END), 0) AS fokus_units
    FROM sales_sell_out s
    JOIN promotor_ids pi ON pi.promotor_id = s.promotor_id
    JOIN product_variants pv ON pv.id = s.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE s.transaction_date BETWEEN v_start AND v_end
      AND s.deleted_at IS NULL
      AND COALESCE(s.is_chip_sale, false) = false
    GROUP BY 1
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'week', week_index,
      'omzet', omzet,
      'fokus_units', fokus_units
    ) ORDER BY week_index
  ), '[]'::json)
  INTO v_weekly
  FROM weekly;

  SELECT COALESCE(json_agg(
    json_build_object(
      'id', sv.id,
      'visit_date', sv.visit_date,
      'notes', sv.notes,
      'store_name', st.store_name
    ) ORDER BY sv.visit_date ASC
  ), '[]'::json)
  INTO v_agenda
  FROM store_visits sv
  LEFT JOIN stores st ON st.id = sv.store_id
  WHERE sv.sator_id = p_sator_id
    AND sv.visit_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '7 days')
  LIMIT 5;

  v_result := json_build_object(
    'period', json_build_object(
      'id', v_period_id,
      'start_date', v_start,
      'end_date', v_end,
      'days', v_days,
      'day_index', v_day_index
    ),
    'counts', json_build_object(
      'stores', v_store_count,
      'promotors', v_promotor_count
    ),
    'targets', json_build_object(
      'sellout_monthly', v_target_sellout,
      'fokus_monthly', v_target_fokus,
      'sellin_monthly', v_target_sellin
    ),
    'actuals', json_build_object(
      'sellout_monthly', v_actual_sellout,
      'fokus_monthly', v_actual_fokus,
      'sellin_monthly', v_actual_sellin
    ),
    'daily_targets', json_build_object(
      'sellout', v_daily_target_sellout,
      'fokus', v_daily_target_fokus,
      'sellin', v_daily_target_sellin
    ),
    'today_actuals', json_build_object(
      'sellout', v_today_sellout,
      'fokus', v_today_fokus,
      'sellin', v_today_sellin
    ),
    'weekly', v_weekly,
    'agenda', v_agenda
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sator_home_summary(uuid) TO authenticated;
