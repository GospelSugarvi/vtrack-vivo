-- Migration: 20260313_sator_home_summary_v2.sql
-- Purpose: Extend SATOR home summary with daily/weekly/monthly tab data

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
  v_month_year text := '';

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
  v_today_units int := 0;

  v_attend_count int := 0;
  v_reported_count int := 0;
  v_report_pending int := 0;

  v_week_index int := 1;
  v_week_start date;
  v_week_end date;
  v_week_pct numeric := 25;
  v_week_target_omzet numeric := 0;
  v_week_actual_omzet numeric := 0;
  v_week_target_fokus numeric := 0;
  v_week_actual_fokus numeric := 0;

  v_weekly json := '[]'::json;
  v_daily_promotors json := '[]'::json;
  v_weekly_promotors json := '[]'::json;
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
  v_month_year := to_char(v_start, 'YYYY-MM');

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
    COALESCE(COUNT(*), 0),
    COALESCE(COUNT(CASE WHEN p.is_focus = true THEN 1 END), 0)
  INTO v_today_sellout, v_today_units, v_today_fokus
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

  -- Attendance (clock-in today)
  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(COUNT(*), 0)
  INTO v_attend_count
  FROM attendance a
  WHERE a.user_id IN (SELECT promotor_id FROM promotor_ids)
    AND a.attendance_date = CURRENT_DATE
    AND a.clock_in IS NOT NULL;

  -- Report status (monthly schedules)
  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT
    COALESCE(COUNT(*) FILTER (WHERE status IN ('submitted', 'approved')), 0),
    COALESCE(COUNT(*) FILTER (WHERE status = 'draft'), 0)
  INTO v_reported_count, v_report_pending
  FROM schedules
  WHERE promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND to_char(schedule_date, 'YYYY-MM') = v_month_year;

  -- Current week
  v_week_index := FLOOR((CURRENT_DATE - v_start) / 7) + 1;
  v_week_start := v_start + (v_week_index - 1) * 7;
  v_week_end := LEAST(v_week_start + 6, v_end);

  SELECT percentage
  INTO v_week_pct
  FROM weekly_targets
  WHERE period_id = v_period_id AND week_number = v_week_index
  LIMIT 1;

  IF v_week_pct IS NULL THEN
    v_week_pct := 25;
  END IF;

  v_week_target_omzet := v_target_sellout * v_week_pct / 100;
  v_week_target_fokus := v_target_fokus * v_week_pct / 100;

  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT
    COALESCE(SUM(s.price_at_transaction), 0),
    COALESCE(COUNT(CASE WHEN p.is_focus = true THEN 1 END), 0)
  INTO v_week_actual_omzet, v_week_actual_fokus
  FROM sales_sell_out s
  JOIN promotor_ids pi ON pi.promotor_id = s.promotor_id
  JOIN product_variants pv ON pv.id = s.variant_id
  JOIN products p ON p.id = pv.product_id
  WHERE s.transaction_date BETWEEN v_week_start AND v_week_end
    AND s.deleted_at IS NULL
    AND COALESCE(s.is_chip_sale, false) = false;

  -- Weekly progress for all weeks
  WITH weeks AS (
    SELECT generate_series(1, CEIL(v_days / 7.0)::int) AS week_index
  ),
  week_ranges AS (
    SELECT
      w.week_index,
      (v_start + (w.week_index - 1) * 7) AS week_start,
      LEAST(v_start + (w.week_index - 1) * 7 + 6, v_end) AS week_end
    FROM weeks w
  ),
  week_targets AS (
    SELECT
      wr.week_index,
      wr.week_start,
      wr.week_end,
      COALESCE(wt.percentage, 25) AS pct,
      (v_target_sellout * COALESCE(wt.percentage, 25) / 100) AS target_omzet
    FROM week_ranges wr
    LEFT JOIN weekly_targets wt
      ON wt.period_id = v_period_id AND wt.week_number = wr.week_index
  ),
  week_actuals AS (
    SELECT
      wt.week_index,
      COALESCE(SUM(s.price_at_transaction), 0) AS actual_omzet
    FROM week_targets wt
    LEFT JOIN sales_sell_out s
      ON s.transaction_date BETWEEN wt.week_start AND wt.week_end
     AND s.deleted_at IS NULL
     AND COALESCE(s.is_chip_sale, false) = false
     AND s.promotor_id IN (
        SELECT promotor_id FROM hierarchy_sator_promotor
        WHERE sator_id = p_sator_id AND active = true
     )
    GROUP BY wt.week_index
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'week', wt.week_index,
      'target_omzet', wt.target_omzet,
      'actual_omzet', wa.actual_omzet,
      'achievement_pct',
        CASE WHEN wt.target_omzet > 0
          THEN (wa.actual_omzet * 100 / wt.target_omzet)
          ELSE 0 END
    ) ORDER BY wt.week_index
  ), '[]'::json)
  INTO v_weekly
  FROM week_targets wt
  JOIN week_actuals wa ON wa.week_index = wt.week_index;

  -- Daily per promotor (focus unit)
  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  promotor_base AS (
    SELECT
      u.id AS promotor_id,
      u.full_name,
      COALESCE(ut.target_fokus_total, 0) AS target_fokus_total
    FROM users u
    JOIN promotor_ids pi ON pi.promotor_id = u.id
    LEFT JOIN user_targets ut
      ON ut.user_id = u.id AND ut.period_id = v_period_id
  ),
  promotor_store AS (
    SELECT DISTINCT ON (aps.promotor_id)
      aps.promotor_id,
      st.store_name
    FROM assignments_promotor_store aps
    JOIN stores st ON st.id = aps.store_id
    WHERE aps.active = true
    ORDER BY aps.promotor_id, aps.created_at DESC
  ),
  promotor_today AS (
    SELECT
      s.promotor_id,
      COUNT(*) FILTER (WHERE p.is_focus = true) AS fokus_units_today
    FROM sales_sell_out s
    JOIN product_variants pv ON pv.id = s.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE s.transaction_date = CURRENT_DATE
      AND s.deleted_at IS NULL
      AND COALESCE(s.is_chip_sale, false) = false
    GROUP BY s.promotor_id
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'promotor_id', pb.promotor_id,
      'name', pb.full_name,
      'store_name', COALESCE(ps.store_name, '-'),
      'target_units', CASE WHEN v_days > 0 THEN (pb.target_fokus_total / v_days) ELSE 0 END,
      'actual_units', COALESCE(pt.fokus_units_today, 0),
      'achievement_pct',
        CASE WHEN v_days > 0 AND (pb.target_fokus_total / v_days) > 0
          THEN (COALESCE(pt.fokus_units_today, 0) * 100 / (pb.target_fokus_total / v_days))
          ELSE 0 END
    ) ORDER BY pb.full_name
  ), '[]'::json)
  INTO v_daily_promotors
  FROM promotor_base pb
  LEFT JOIN promotor_store ps ON ps.promotor_id = pb.promotor_id
  LEFT JOIN promotor_today pt ON pt.promotor_id = pb.promotor_id;

  -- Weekly per promotor (all units)
  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  promotor_base AS (
    SELECT
      u.id AS promotor_id,
      u.full_name,
      COALESCE(ut.target_fokus_total, 0) AS target_fokus_total
    FROM users u
    JOIN promotor_ids pi ON pi.promotor_id = u.id
    LEFT JOIN user_targets ut
      ON ut.user_id = u.id AND ut.period_id = v_period_id
  ),
  promotor_week AS (
    SELECT
      s.promotor_id,
      COUNT(*) AS units_week
    FROM sales_sell_out s
    WHERE s.transaction_date BETWEEN v_week_start AND v_week_end
      AND s.deleted_at IS NULL
      AND COALESCE(s.is_chip_sale, false) = false
    GROUP BY s.promotor_id
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'promotor_id', pb.promotor_id,
      'name', pb.full_name,
      'units_week', COALESCE(pw.units_week, 0),
      'target_units', (pb.target_fokus_total * v_week_pct / 100),
      'achievement_pct',
        CASE WHEN (pb.target_fokus_total * v_week_pct / 100) > 0
          THEN (COALESCE(pw.units_week, 0) * 100 / (pb.target_fokus_total * v_week_pct / 100))
          ELSE 0 END
    ) ORDER BY pb.full_name
  ), '[]'::json)
  INTO v_weekly_promotors
  FROM promotor_base pb
  LEFT JOIN promotor_week pw ON pw.promotor_id = pb.promotor_id;

  -- Agenda items
  SELECT COALESCE(json_agg(item), '[]'::json)
  INTO v_agenda
  FROM (
    SELECT json_build_object(
      'type', 'schedule',
      'title', 'Approve Jadwal',
      'sub', v_report_pending::text || ' pending',
      'status', CASE WHEN v_report_pending > 0 THEN 'pending' ELSE 'ok' END
    ) AS item
    UNION ALL
    SELECT json_build_object(
      'type', 'visiting',
      'title', 'Visiting',
      'sub', COALESCE(st.store_name, 'Tidak ada visiting'),
      'status', CASE WHEN sv.id IS NULL THEN 'idle' ELSE 'done' END
    )
    FROM (
      SELECT id, store_id
      FROM store_visits
      WHERE sator_id = p_sator_id
        AND visit_date = CURRENT_DATE
      ORDER BY created_at DESC
      LIMIT 1
    ) sv
    LEFT JOIN stores st ON st.id = sv.store_id
    UNION ALL
    SELECT json_build_object(
      'type', 'sellin',
      'title', 'Finalisasi Sell In',
      'sub', COALESCE(COUNT(*),0)::text || ' order pending',
      'status', CASE WHEN COUNT(*) > 0 THEN 'process' ELSE 'ok' END
    )
    FROM orders
    WHERE sator_id = p_sator_id
      AND status IN ('pending','processing')
    UNION ALL
    SELECT json_build_object(
      'type', 'imei',
      'title', 'Penormalan IMEI',
      'sub', COALESCE(COUNT(*),0)::text || ' unit',
      'status', CASE WHEN COUNT(*) > 0 THEN 'review' ELSE 'ok' END
    )
    FROM imei_records
    WHERE promotor_id IN (
      SELECT promotor_id FROM hierarchy_sator_promotor
      WHERE sator_id = p_sator_id AND active = true
    )
      AND normalization_status <> 'completed'
  ) t;

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
    'daily', json_build_object(
      'target_sellout', v_daily_target_sellout,
      'actual_sellout', v_today_sellout,
      'target_fokus', v_daily_target_fokus,
      'actual_fokus', v_today_fokus,
      'target_sellin', v_daily_target_sellin,
      'actual_sellin', v_today_sellin,
      'units_sold', v_today_units,
      'attendance_present', v_attend_count,
      'attendance_total', v_promotor_count,
      'reports_done', v_reported_count,
      'reports_pending', v_report_pending
    ),
    'weekly', json_build_object(
      'week_index', v_week_index,
      'week_start', v_week_start,
      'week_end', v_week_end,
      'target_omzet', v_week_target_omzet,
      'actual_omzet', v_week_actual_omzet,
      'target_fokus', v_week_target_fokus,
      'actual_fokus', v_week_actual_fokus,
      'week_pct', v_week_pct,
      'progress', v_weekly
    ),
    'monthly', json_build_object(
      'target_omzet', v_target_sellout,
      'actual_omzet', v_actual_sellout,
      'target_fokus', v_target_fokus,
      'actual_fokus', v_actual_fokus,
      'target_sellin', v_target_sellin,
      'actual_sellin', v_actual_sellin,
      'target_per_day', CASE WHEN v_days - v_day_index > 0
        THEN (v_target_sellout - v_actual_sellout) / (v_days - v_day_index)
        ELSE 0 END
    ),
    'daily_promotors', v_daily_promotors,
    'weekly_promotors', v_weekly_promotors,
    'agenda', v_agenda
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sator_home_summary(uuid) TO authenticated;
