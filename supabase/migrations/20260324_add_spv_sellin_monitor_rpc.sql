DROP FUNCTION IF EXISTS public.get_spv_sellin_monitor(UUID, TEXT, DATE);
DROP FUNCTION IF EXISTS public.get_spv_sellin_monitor(UUID, TEXT, DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_spv_sellin_monitor(
  p_spv_id UUID,
  p_filter TEXT DEFAULT 'today',
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_filter TEXT := LOWER(COALESCE(p_filter, 'today'));
  v_range_start DATE;
  v_range_end DATE;
  v_period_id UUID;
  v_period_start DATE;
  v_period_end DATE;
  v_period_days INTEGER := 0;
  v_overlap_days INTEGER := 0;
  v_target_ratio NUMERIC := 0;
  v_result JSON;
BEGIN
  IF p_spv_id IS NULL THEN
    RAISE EXCEPTION 'p_spv_id is required';
  END IF;

  IF v_filter NOT IN ('today', 'custom') THEN
    RAISE EXCEPTION 'p_filter must be today or custom';
  END IF;

  IF v_filter = 'today' THEN
    v_range_start := CURRENT_DATE;
    v_range_end := CURRENT_DATE;
  ELSE
    v_range_start := COALESCE(p_start_date, CURRENT_DATE);
    v_range_end := COALESCE(p_end_date, v_range_start);
  END IF;

  IF v_range_start > v_range_end THEN
    RAISE EXCEPTION 'p_start_date must be before or equal to p_end_date';
  END IF;

  SELECT tp.id, tp.start_date, tp.end_date
  INTO v_period_id, v_period_start, v_period_end
  FROM public.target_periods tp
  WHERE tp.deleted_at IS NULL
    AND tp.start_date <= v_range_end
    AND tp.end_date >= v_range_start
  ORDER BY CASE WHEN tp.status = 'active' THEN 0 ELSE 1 END, tp.start_date DESC
  LIMIT 1;

  IF v_period_id IS NOT NULL THEN
    v_period_days := GREATEST((v_period_end - v_period_start + 1), 0);
    v_overlap_days := GREATEST(
      LEAST(v_range_end, v_period_end) - GREATEST(v_range_start, v_period_start) + 1,
      0
    );
    IF v_period_days > 0 AND v_overlap_days > 0 THEN
      v_target_ratio := v_overlap_days::NUMERIC / v_period_days::NUMERIC;
    END IF;
  END IF;

  WITH linked_sators AS (
    SELECT
      hs.sator_id,
      COALESCE(NULLIF(u.full_name, ''), 'SATOR') AS sator_name
    FROM public.hierarchy_spv_sator hs
    JOIN public.users u ON u.id = hs.sator_id
    WHERE hs.spv_id = p_spv_id
      AND hs.active = true
      AND u.deleted_at IS NULL
  ),
  sator_targets AS (
    SELECT
      ls.sator_id,
      COALESCE(ut.target_sell_in, 0)::NUMERIC * v_target_ratio AS target_value
    FROM linked_sators ls
    LEFT JOIN public.user_targets ut
      ON ut.user_id = ls.sator_id
     AND ut.period_id = v_period_id
  ),
  actual_rows AS (
    SELECT
      s.sator_id,
      s.store_id,
      COALESCE(st.store_name, 'Toko') AS store_name,
      COUNT(DISTINCT COALESCE(s.source_order_id::TEXT, s.id::TEXT))::INTEGER AS order_count,
      COALESCE(SUM(s.total_value), 0)::NUMERIC AS actual_value
    FROM public.sales_sell_in s
    JOIN linked_sators ls ON ls.sator_id = s.sator_id
    LEFT JOIN public.stores st ON st.id = s.store_id
    WHERE s.deleted_at IS NULL
      AND s.transaction_date BETWEEN v_range_start AND v_range_end
    GROUP BY s.sator_id, s.store_id, st.store_name
  ),
  finalized_rows AS (
    SELECT
      o.sator_id,
      o.store_id,
      COALESCE(st.store_name, 'Toko') AS store_name,
      COUNT(*)::INTEGER AS finalized_order_count,
      COALESCE(SUM(o.total_value), 0)::NUMERIC AS finalized_value
    FROM public.sell_in_orders o
    JOIN linked_sators ls ON ls.sator_id = o.sator_id
    LEFT JOIN public.stores st ON st.id = o.store_id
    WHERE o.status = 'finalized'
      AND o.order_date BETWEEN v_range_start AND v_range_end
    GROUP BY o.sator_id, o.store_id, st.store_name
  ),
  pending_rows AS (
    SELECT
      ls.sator_id,
      x.store_id,
      COALESCE(NULLIF(x.store_name, ''), st.store_name, 'Toko') AS store_name,
      COUNT(*)::INTEGER AS pending_order_count,
      COALESCE(SUM(x.total_value), 0)::NUMERIC AS pending_value
    FROM linked_sators ls
    CROSS JOIN LATERAL json_to_recordset(
      COALESCE(public.get_pending_orders(ls.sator_id), '[]'::json)
    ) AS x(
      id UUID,
      store_id UUID,
      store_name TEXT,
      group_id UUID,
      group_name TEXT,
      order_date DATE,
      source TEXT,
      total_items INTEGER,
      total_qty INTEGER,
      total_value NUMERIC,
      status TEXT,
      created_at TIMESTAMPTZ
    )
    LEFT JOIN public.stores st ON st.id = x.store_id
    WHERE x.order_date BETWEEN v_range_start AND v_range_end
    GROUP BY ls.sator_id, x.store_id, COALESCE(NULLIF(x.store_name, ''), st.store_name, 'Toko')
  ),
  store_rollups AS (
    SELECT
      base.sator_id,
      base.store_id,
      base.store_name,
      COALESCE(ar.actual_value, 0)::NUMERIC AS actual_value,
      COALESCE(ar.order_count, 0)::INTEGER AS actual_order_count,
      COALESCE(fr.finalized_order_count, 0)::INTEGER AS finalized_order_count,
      COALESCE(fr.finalized_value, 0)::NUMERIC AS finalized_value,
      COALESCE(pr.pending_order_count, 0)::INTEGER AS pending_order_count,
      COALESCE(pr.pending_value, 0)::NUMERIC AS pending_value
    FROM (
      SELECT sator_id, store_id, store_name FROM actual_rows
      UNION
      SELECT sator_id, store_id, store_name FROM finalized_rows
      UNION
      SELECT sator_id, store_id, store_name FROM pending_rows
    ) base
    LEFT JOIN actual_rows ar
      ON ar.sator_id = base.sator_id
     AND ar.store_id = base.store_id
    LEFT JOIN finalized_rows fr
      ON fr.sator_id = base.sator_id
     AND fr.store_id = base.store_id
    LEFT JOIN pending_rows pr
      ON pr.sator_id = base.sator_id
     AND pr.store_id = base.store_id
  ),
  sator_rollups AS (
    SELECT
      ls.sator_id,
      ls.sator_name,
      COALESCE(st.target_value, 0)::NUMERIC AS target_value,
      COALESCE(SUM(sr.actual_value), 0)::NUMERIC AS actual_value,
      COALESCE(SUM(sr.pending_order_count), 0)::INTEGER AS pending_order_count,
      COALESCE(SUM(sr.finalized_order_count), 0)::INTEGER AS finalized_order_count
    FROM linked_sators ls
    LEFT JOIN sator_targets st ON st.sator_id = ls.sator_id
    LEFT JOIN store_rollups sr ON sr.sator_id = ls.sator_id
    GROUP BY ls.sator_id, ls.sator_name, st.target_value
  ),
  summary_rollup AS (
    SELECT
      COALESCE(SUM(target_value), 0)::NUMERIC AS total_target_value,
      COALESCE(SUM(actual_value), 0)::NUMERIC AS total_actual_value,
      COALESCE(SUM(pending_order_count), 0)::INTEGER AS total_pending_orders,
      COALESCE(SUM(finalized_order_count), 0)::INTEGER AS total_finalized_orders
    FROM sator_rollups
  )
  SELECT json_build_object(
    'filter', v_filter,
    'range', json_build_object(
      'start_date', v_range_start,
      'end_date', v_range_end,
      'reference_date', CURRENT_DATE,
      'label', CASE
        WHEN v_filter = 'today' THEN TO_CHAR(v_range_start, 'DD Mon YYYY')
        ELSE TO_CHAR(v_range_start, 'DD Mon YYYY') || ' - ' || TO_CHAR(v_range_end, 'DD Mon YYYY')
      END
    ),
    'summary', (
      SELECT json_build_object(
        'target_value', total_target_value,
        'actual_value', total_actual_value,
        'achievement_pct', CASE
          WHEN total_target_value > 0 THEN ROUND(total_actual_value * 100 / total_target_value, 1)
          ELSE 0
        END,
        'gap_value', GREATEST(total_target_value - total_actual_value, 0),
        'pending_order_count', total_pending_orders,
        'finalized_order_count', total_finalized_orders
      )
      FROM summary_rollup
    ),
    'sators', COALESCE((
      SELECT json_agg(
        json_build_object(
          'sator_id', sr.sator_id,
          'sator_name', sr.sator_name,
          'target_value', sr.target_value,
          'actual_value', sr.actual_value,
          'achievement_pct', CASE
            WHEN sr.target_value > 0 THEN ROUND(sr.actual_value * 100 / sr.target_value, 1)
            ELSE 0
          END,
          'gap_value', GREATEST(sr.target_value - sr.actual_value, 0),
          'pending_order_count', sr.pending_order_count,
          'finalized_order_count', sr.finalized_order_count,
          'stores', COALESCE((
            SELECT json_agg(
              json_build_object(
                'store_id', st.store_id,
                'store_name', st.store_name,
                'actual_value', st.actual_value,
                'actual_order_count', st.actual_order_count,
                'pending_order_count', st.pending_order_count,
                'finalized_order_count', st.finalized_order_count,
                'contribution_pct', CASE
                  WHEN sr.actual_value > 0 THEN ROUND(st.actual_value * 100 / sr.actual_value, 1)
                  ELSE 0
                END
              )
              ORDER BY st.actual_value DESC, st.finalized_order_count DESC, st.store_name
            )
            FROM store_rollups st
            WHERE st.sator_id = sr.sator_id
          ), '[]'::json)
        )
        ORDER BY
          CASE WHEN sr.target_value > 0 THEN sr.actual_value / sr.target_value ELSE 0 END DESC,
          sr.actual_value DESC,
          sr.sator_name
      )
      FROM sator_rollups sr
    ), '[]'::json)
  )
  INTO v_result;

  RETURN COALESCE(
    v_result,
    json_build_object(
      'filter', v_filter,
      'range', json_build_object(
        'start_date', v_range_start,
        'end_date', v_range_end,
        'reference_date', CURRENT_DATE,
        'label', TO_CHAR(v_range_start, 'DD Mon YYYY')
      ),
      'summary', json_build_object(
        'target_value', 0,
        'actual_value', 0,
        'achievement_pct', 0,
        'gap_value', 0,
        'pending_order_count', 0,
        'finalized_order_count', 0
      ),
      'sators', '[]'::json
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_spv_sellin_monitor(UUID, TEXT, DATE, DATE) TO authenticated;
