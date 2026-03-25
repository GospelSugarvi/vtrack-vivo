-- Migration: 20260313_sator_bonus_detail.sql
-- Purpose: Compute detailed SATOR bonus (KPI + poin Sell Out + reward khusus)

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
  v_point_value numeric := 1000; -- 1 poin = Rp 1.000 (sesuai dokumen)
  v_potential_kpi_bonus numeric := 0;
  v_effective_kpi_bonus numeric := 0;

  v_special_bonus numeric := 0;
  v_total_bonus_effective numeric := 0;
  v_total_bonus_potential numeric := 0;
BEGIN
  -- 1) Tentukan periode target aktif (sama seperti get_sator_kpi_summary)
  SELECT id, start_date, end_date
  INTO v_period_id, v_start, v_end
  FROM target_periods
  WHERE start_date <= CURRENT_DATE
    AND end_date >= CURRENT_DATE
  LIMIT 1;

  IF v_period_id IS NULL THEN
    -- Tidak ada periode aktif, kembalikan nol tapi tetap format lengkap
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
        'special_bonus_effective', 0
      ),
      'totals', json_build_object(
        'total_bonus_effective', 0,
        'total_bonus_potential', 0
      )
    );
    RETURN v_result;
  END IF;

  v_period_month := to_char(v_start, 'YYYY-MM');

  -- 2) Ambil KPI summary yang sudah dihitung live
  SELECT public.get_sator_kpi_summary(p_sator_id)
  INTO v_kpi;

  IF v_kpi IS NOT NULL THEN
    v_total_kpi_score := COALESCE( (v_kpi->>'total_score')::numeric, 0 );
  ELSE
    v_total_kpi_score := 0;
  END IF;

  v_kpi_eligible := v_total_kpi_score >= 80;

  -- 3) Hitung total poin Sell Out tim SATOR untuk periode ini
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
  )
  SELECT COALESCE(SUM(pr.points_per_unit), 0)
  INTO v_total_points
  FROM sales_with_price swp
  JOIN point_ranges pr
    ON pr.role = 'sator'
   AND pr.data_source = 'sell_out'
   AND swp.price_at_transaction >= pr.min_price
   AND (
        pr.max_price IS NULL
        OR pr.max_price = 0
        OR swp.price_at_transaction <= pr.max_price
   );

  v_total_points := COALESCE(v_total_points, 0);
  v_potential_kpi_bonus := v_total_points * v_point_value;
  v_effective_kpi_bonus := CASE
    WHEN v_kpi_eligible THEN v_potential_kpi_bonus
    ELSE 0
  END;

  -- 4) Bonus reward tipe khusus (gunakan sator_rewards sebagai sumber realisasi)
  SELECT COALESCE(SUM(amount), 0)
  INTO v_special_bonus
  FROM sator_rewards
  WHERE sator_id = p_sator_id
    AND period_month = v_period_month
    AND reward_type IN ('special', 'incentive');

  v_special_bonus := COALESCE(v_special_bonus, 0);

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
      'effective_kpi_bonus', v_effective_kpi_bonus
    ),
    'special_rewards', json_build_object(
      'special_bonus_effective', v_special_bonus
    ),
    'totals', json_build_object(
      'total_bonus_effective', v_total_bonus_effective,
      'total_bonus_potential', v_total_bonus_potential
    )
  );

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sator_bonus_detail(uuid) TO authenticated;

