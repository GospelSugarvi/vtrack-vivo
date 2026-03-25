CREATE OR REPLACE FUNCTION public.get_sator_compact_summary(
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  sator_id UUID,
  sator_name TEXT,
  sellout_target NUMERIC,
  sellout_actual NUMERIC,
  sellout_pct NUMERIC,
  focus_target NUMERIC,
  focus_actual NUMERIC,
  focus_pct NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  WITH promotor_sator AS (
    SELECT
      u.id AS promotor_id,
      chosen.sator_id,
      COALESCE(s.full_name, 'Tanpa SATOR') AS sator_name
    FROM public.users u
    LEFT JOIN LATERAL (
      SELECT hsp.sator_id
      FROM public.hierarchy_sator_promotor hsp
      JOIN public.users su
        ON su.id = hsp.sator_id
       AND su.role = 'sator'
      WHERE hsp.promotor_id = u.id
        AND hsp.active = true
      ORDER BY hsp.created_at DESC, hsp.sator_id
      LIMIT 1
    ) chosen ON TRUE
    LEFT JOIN public.users s ON s.id = chosen.sator_id
    WHERE u.role = 'promotor'
      AND u.deleted_at IS NULL
  ),
  promotor_daily AS (
    SELECT
      ps.sator_id,
      ps.sator_name,
      ps.promotor_id,
      COALESCE(d.target_daily_all_type, 0)::NUMERIC AS sellout_target,
      COALESCE(d.actual_daily_all_type, 0)::NUMERIC AS sellout_actual,
      COALESCE(d.target_daily_focus, 0)::NUMERIC AS focus_target,
      COALESCE(d.actual_daily_focus, 0)::NUMERIC AS focus_actual
    FROM promotor_sator ps
    LEFT JOIN LATERAL public.get_daily_target_dashboard(ps.promotor_id, p_date) d
      ON TRUE
  )
  SELECT
    pd.sator_id,
    pd.sator_name,
    COALESCE(SUM(pd.sellout_target), 0)::NUMERIC AS sellout_target,
    COALESCE(SUM(pd.sellout_actual), 0)::NUMERIC AS sellout_actual,
    CASE
      WHEN COALESCE(SUM(pd.sellout_target), 0) > 0
        THEN ROUND((COALESCE(SUM(pd.sellout_actual), 0) / SUM(pd.sellout_target)) * 100, 1)
      ELSE 0
    END::NUMERIC AS sellout_pct,
    COALESCE(SUM(pd.focus_target), 0)::NUMERIC AS focus_target,
    COALESCE(SUM(pd.focus_actual), 0)::NUMERIC AS focus_actual,
    CASE
      WHEN COALESCE(SUM(pd.focus_target), 0) > 0
        THEN ROUND((COALESCE(SUM(pd.focus_actual), 0) / SUM(pd.focus_target)) * 100, 1)
      ELSE 0
    END::NUMERIC AS focus_pct
  FROM promotor_daily pd
  GROUP BY pd.sator_id, pd.sator_name
  ORDER BY pd.sator_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_sator_compact_summary(DATE) TO authenticated;
