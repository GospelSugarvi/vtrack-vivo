-- Migration: 20260313_fix_sator_kpi_bonus_logic.sql
-- Fix KPI total to include KPI MA and align bonus detail with KPI eligibility + point + special rewards rules

-- 1) Fix SATOR KPI summary to include KPI MA weight
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
    + COALESCE((SELECT weight FROM kpi_settings WHERE role='sator' AND kpi_name ILIKE '%KPI MA%'), 0) * v_ma_score
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

-- 2) Update SATOR bonus detail to apply KPI eligibility + poin + reward khusus (dengan denda)
CREATE OR REPLACE FUNCTION public.get_sator_bonus_detail(
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
  v_period_month text;

  v_kpi json;
  v_total_kpi_score numeric := 0;
  v_kpi_eligible boolean := false;

  v_total_points numeric := 0;
  v_point_value numeric := 1000; -- 1 poin = Rp 1.000
  v_potential_kpi_bonus numeric := 0;
  v_effective_kpi_bonus numeric := 0;
  v_points_breakdown json := '[]'::json;

  v_special_reward_total numeric := 0;
  v_special_penalty_total numeric := 0;
  v_special_bonus numeric := 0;
  v_rewards_breakdown json := '[]'::json;

  v_total_bonus_effective numeric := 0;
  v_total_bonus_potential numeric := 0;
BEGIN
  -- 1) Tentukan periode target aktif
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM target_periods
  WHERE start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE
  LIMIT 1;

  IF v_period_id IS NULL THEN
    v_result := json_build_object(
      'period_month', NULL,
      'kpi', json_build_object(
        'total_score', 0,
        'eligible', false,
        'min_required', 80
      ),
      'points', json_build_object(
        'total_points', 0,
        'point_value', v_point_value,
        'potential_kpi_bonus', 0,
        'effective_kpi_bonus', 0
      ),
      'special_rewards', json_build_object(
        'special_bonus_effective', 0,
        'reward_total', 0,
        'penalty_total', 0
      ),
      'totals', json_build_object(
        'total_bonus_effective', 0,
        'total_bonus_potential', 0
      )
    );
    RETURN v_result;
  END IF;

  v_period_month := to_char(v_start, 'YYYY-MM');

  -- 2) Ambil KPI summary
  SELECT public.get_sator_kpi_summary(p_sator_id)
  INTO v_kpi;

  IF v_kpi IS NOT NULL THEN
    v_total_kpi_score := COALESCE( (v_kpi->>'total_score')::numeric, 0 );
  ELSE
    v_total_kpi_score := 0;
  END IF;

  v_kpi_eligible := v_total_kpi_score >= 80;

  -- 3) Hitung total poin Sell Out tim SATOR untuk periode ini (dengan breakdown)
  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id
      AND active = true
  ),
  sales_with_price AS (
    SELECT
      s.id,
      s.price_at_transaction
    FROM sales_sell_out s
    JOIN promotor_ids pi ON pi.promotor_id = s.promotor_id
    WHERE s.transaction_date BETWEEN v_start AND v_end
      AND s.deleted_at IS NULL
      AND COALESCE(s.is_chip_sale, false) = false
  ),
  range_counts AS (
    SELECT
      pr.id,
      pr.min_price,
      pr.max_price,
      pr.points_per_unit,
      COALESCE(COUNT(swp.id), 0) AS units
    FROM point_ranges pr
    LEFT JOIN sales_with_price swp
      ON swp.price_at_transaction >= pr.min_price
     AND (
          pr.max_price IS NULL
          OR pr.max_price = 0
          OR swp.price_at_transaction <= pr.max_price
     )
    WHERE pr.role = 'sator'
      AND pr.data_source = 'sell_out'
    GROUP BY pr.id, pr.min_price, pr.max_price, pr.points_per_unit
  )
  SELECT
    COALESCE(SUM(units * points_per_unit), 0),
    COALESCE(json_agg(
      json_build_object(
        'min_price', min_price,
        'max_price', max_price,
        'points_per_unit', points_per_unit,
        'units', units,
        'total_points', (units * points_per_unit)
      )
      ORDER BY min_price
    ), '[]'::json)
  INTO v_total_points, v_points_breakdown
  FROM range_counts;

  v_total_points := COALESCE(v_total_points, 0);
  v_potential_kpi_bonus := v_total_points * v_point_value;
  v_effective_kpi_bonus := CASE
    WHEN v_kpi_eligible THEN v_potential_kpi_bonus
    ELSE 0
  END;

  -- 4) Bonus reward tipe khusus (berdasarkan rule admin) + breakdown
  WITH promotor_ids AS (
    SELECT promotor_id
    FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id
      AND active = true
  ),
  reward_rules AS (
    SELECT
      sr.*,
      p.model_name AS product_model_name,
      fb.bundle_name AS fokus_bundle_name,
      sb.bundle_name AS special_bundle_name,
      sb.period_id AS special_period_id,
      fb.product_types AS bundle_product_types
    FROM special_rewards sr
    LEFT JOIN products p ON p.id = sr.product_id
    LEFT JOIN fokus_bundles fb ON fb.id = sr.bundle_id
    LEFT JOIN special_focus_bundles sb ON sb.id = sr.special_bundle_id
    WHERE sr.role = 'sator'
      AND (sr.special_bundle_id IS NULL OR sb.period_id = v_period_id)
  ),
  reward_units AS (
    SELECT
      rr.id,
      rr.product_model_name,
      rr.fokus_bundle_name,
      rr.special_bundle_name,
      rr.min_unit,
      rr.max_unit,
      rr.reward_amount,
      rr.penalty_threshold,
      rr.penalty_amount,
      rr.data_source,
      rr.product_id,
      rr.bundle_id,
      rr.special_bundle_id,
      rr.product_name,
      rr.bundle_product_types,
      COALESCE(
        CASE
          WHEN rr.data_source = 'sell_out' THEN (
            SELECT COUNT(*)
            FROM sales_sell_out s
            JOIN promotor_ids pi ON pi.promotor_id = s.promotor_id
            JOIN product_variants pv ON pv.id = s.variant_id
            JOIN products p ON p.id = pv.product_id
            WHERE s.transaction_date BETWEEN v_start AND v_end
              AND s.deleted_at IS NULL
              AND COALESCE(s.is_chip_sale, false) = false
              AND (
                (rr.product_id IS NOT NULL AND p.id = rr.product_id)
                OR (
                  rr.special_bundle_id IS NOT NULL
                  AND p.id IN (
                    SELECT product_id
                    FROM special_focus_bundle_products
                    WHERE bundle_id = rr.special_bundle_id
                  )
                )
                OR (
                  rr.bundle_id IS NOT NULL
                  AND (
                    p.id IN (
                      SELECT product_id
                      FROM reward_bundle_products
                      WHERE bundle_id = rr.bundle_id
                    )
                    OR (
                      rr.bundle_product_types IS NOT NULL
                      AND p.model_name = ANY(rr.bundle_product_types)
                    )
                  )
                )
                OR (
                  rr.product_id IS NULL
                  AND rr.bundle_id IS NULL
                  AND rr.special_bundle_id IS NULL
                  AND rr.product_name IS NOT NULL
                  AND p.model_name ILIKE rr.product_name
                )
              )
          )
          WHEN rr.data_source = 'sell_in' THEN (
            SELECT COALESCE(SUM(si.qty), 0)
            FROM sales_sell_in si
            JOIN product_variants pv ON pv.id = si.variant_id
            JOIN products p ON p.id = pv.product_id
            WHERE si.sator_id = p_sator_id
              AND si.transaction_date BETWEEN v_start AND v_end
              AND si.deleted_at IS NULL
              AND (
                (rr.product_id IS NOT NULL AND p.id = rr.product_id)
                OR (
                  rr.special_bundle_id IS NOT NULL
                  AND p.id IN (
                    SELECT product_id
                    FROM special_focus_bundle_products
                    WHERE bundle_id = rr.special_bundle_id
                  )
                )
                OR (
                  rr.bundle_id IS NOT NULL
                  AND (
                    p.id IN (
                      SELECT product_id
                      FROM reward_bundle_products
                      WHERE bundle_id = rr.bundle_id
                    )
                    OR (
                      rr.bundle_product_types IS NOT NULL
                      AND p.model_name = ANY(rr.bundle_product_types)
                    )
                  )
                )
                OR (
                  rr.product_id IS NULL
                  AND rr.bundle_id IS NULL
                  AND rr.special_bundle_id IS NULL
                  AND rr.product_name IS NOT NULL
                  AND p.model_name ILIKE rr.product_name
                )
              )
          )
          ELSE 0
        END,
        0
      ) AS actual_units
    FROM reward_rules rr
  ),
  reward_calc AS (
    SELECT
      id,
      actual_units,
      CASE
        WHEN actual_units >= min_unit
          AND (max_unit IS NULL OR max_unit = 0 OR actual_units <= max_unit)
          THEN reward_amount
        ELSE 0
      END AS reward_effective,
      CASE
        WHEN min_unit > 0
          AND (actual_units * 100.0 / min_unit) < COALESCE(penalty_threshold, 0)
          THEN COALESCE(penalty_amount, 0)
        ELSE 0
      END AS penalty_effective
    FROM reward_units
  )
  SELECT
    COALESCE(SUM(reward_effective), 0),
    COALESCE(SUM(penalty_effective), 0),
    COALESCE(json_agg(
      json_build_object(
        'rule_id', rc.id,
        'name', COALESCE(rc.product_model_name, rc.special_bundle_name, rc.fokus_bundle_name, rc.product_name, 'Bundle'),
        'data_source', rc.data_source,
        'min_unit', rc.min_unit,
        'max_unit', rc.max_unit,
        'actual_units', rc.actual_units,
        'reward_amount', rc.reward_amount,
        'penalty_threshold', rc.penalty_threshold,
        'penalty_amount', rc.penalty_amount,
        'reward_effective', rc.reward_effective,
        'penalty_effective', rc.penalty_effective,
        'net_bonus', (rc.reward_effective - rc.penalty_effective)
      )
      ORDER BY COALESCE(rc.product_model_name, rc.special_bundle_name, rc.fokus_bundle_name, rc.product_name, 'Bundle')
    ), '[]'::json)
  INTO v_special_reward_total, v_special_penalty_total, v_rewards_breakdown
  FROM reward_calc rc;

  v_special_reward_total := COALESCE(v_special_reward_total, 0);
  v_special_penalty_total := COALESCE(v_special_penalty_total, 0);
  v_special_bonus := v_special_reward_total - v_special_penalty_total;

  -- 5) Total gabungan
  v_total_bonus_effective := v_effective_kpi_bonus + v_special_bonus;
  v_total_bonus_potential := v_potential_kpi_bonus + v_special_bonus;

  -- 6) Susun hasil JSON lengkap
  v_result := json_build_object(
    'period_month', v_period_month,
    'kpi', json_build_object(
      'total_score', v_total_kpi_score,
      'eligible', v_kpi_eligible,
      'min_required', 80
    ),
    'points', json_build_object(
      'total_points', v_total_points,
      'point_value', v_point_value,
      'potential_kpi_bonus', v_potential_kpi_bonus,
      'effective_kpi_bonus', v_effective_kpi_bonus,
      'breakdown', v_points_breakdown
    ),
    'special_rewards', json_build_object(
      'special_bonus_effective', v_special_bonus,
      'reward_total', v_special_reward_total,
      'penalty_total', v_special_penalty_total,
      'breakdown', v_rewards_breakdown
    ),
    'totals', json_build_object(
      'total_bonus_effective', v_total_bonus_effective,
      'total_bonus_potential', v_total_bonus_potential
    )
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sator_kpi_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sator_bonus_detail(UUID) TO authenticated;
