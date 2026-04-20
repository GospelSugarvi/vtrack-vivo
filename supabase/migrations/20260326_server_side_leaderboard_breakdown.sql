-- Move leaderboard type/bonus breakdown computation to server-side
-- so client only renders pre-aggregated data.

DROP FUNCTION IF EXISTS public.get_daily_ranking(DATE, UUID, INTEGER);

CREATE FUNCTION public.get_daily_ranking(
  p_date DATE DEFAULT CURRENT_DATE,
  p_area_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  rank INTEGER,
  promotor_id UUID,
  promotor_name TEXT,
  store_name TEXT,
  total_sales INTEGER,
  total_bonus NUMERIC,
  daily_target NUMERIC,
  has_sold BOOLEAN,
  primary_type TEXT,
  extra_type_count INTEGER,
  type_breakdown JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH sale_bonus AS (
    SELECT
      so.id AS sales_sell_out_id,
      CASE
        WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC
        WHEN COALESCE(so.estimated_bonus, 0) > 0 THEN COALESCE(so.estimated_bonus, 0)::NUMERIC
        ELSE 0::NUMERIC
      END AS total_bonus
    FROM public.sales_sell_out so
    LEFT JOIN public.sales_bonus_events sbe
      ON sbe.sales_sell_out_id = so.id
    GROUP BY so.id, so.estimated_bonus
  ),
  sale_rows AS (
    SELECT
      so.promotor_id,
      TRIM(
        CONCAT_WS(
          ' ',
          NULLIF(TRIM(COALESCE(p.model_name, '')), ''),
          NULLIF(TRIM(COALESCE(pv.ram_rom, '')), '')
        )
      ) AS type_label,
      COALESCE(sb.total_bonus, 0)::NUMERIC AS bonus_amount
    FROM public.sales_sell_out so
    JOIN public.product_variants pv ON pv.id = so.variant_id
    JOIN public.products p ON p.id = pv.product_id
    LEFT JOIN sale_bonus sb ON sb.sales_sell_out_id = so.id
    WHERE so.transaction_date = p_date
      AND so.deleted_at IS NULL
      AND COALESCE(so.is_chip_sale, false) = false
  ),
  promotor_totals AS (
    SELECT
      sr.promotor_id,
      COUNT(*)::INTEGER AS sales_count,
      COALESCE(SUM(sr.bonus_amount), 0)::NUMERIC AS bonus_total
    FROM sale_rows sr
    GROUP BY sr.promotor_id
  ),
  type_totals AS (
    SELECT
      sr.promotor_id,
      CASE
        WHEN COALESCE(NULLIF(sr.type_label, ''), '') = '' THEN '-'
        ELSE sr.type_label
      END AS type_label,
      COUNT(*)::INTEGER AS unit_count,
      COALESCE(SUM(sr.bonus_amount), 0)::NUMERIC AS bonus_total
    FROM sale_rows sr
    GROUP BY sr.promotor_id, 2
  ),
  type_ranked AS (
    SELECT
      tt.*,
      ROW_NUMBER() OVER (
        PARTITION BY tt.promotor_id
        ORDER BY tt.unit_count DESC, tt.bonus_total DESC, tt.type_label
      ) AS row_num,
      COUNT(*) OVER (PARTITION BY tt.promotor_id)::INTEGER AS type_count
    FROM type_totals tt
  ),
  type_agg AS (
    SELECT
      tr.promotor_id,
      MAX(CASE WHEN tr.row_num = 1 THEN tr.type_label END) AS primary_type,
      MAX(tr.type_count)::INTEGER AS type_count,
      JSONB_AGG(
        JSONB_BUILD_OBJECT(
          'type_label', tr.type_label,
          'unit_count', tr.unit_count,
          'bonus_total', tr.bonus_total
        )
        ORDER BY tr.unit_count DESC, tr.bonus_total DESC, tr.type_label
      ) AS type_breakdown
    FROM type_ranked tr
    GROUP BY tr.promotor_id
  ),
  all_promotors AS (
    SELECT
      u.id AS promotor_id,
      COALESCE(NULLIF(BTRIM(u.nickname), ''), u.full_name) AS promotor_name,
      st.store_name,
      COALESCE(pt.sales_count, 0)::INTEGER AS total_sales,
      COALESCE(pt.bonus_total, 0)::NUMERIC AS total_bonus,
      COALESCE(dtd.target_daily_all_type, 0)::NUMERIC AS daily_target,
      (COALESCE(pt.sales_count, 0) > 0) AS has_sold,
      COALESCE(ta.primary_type, '-') AS primary_type,
      GREATEST(COALESCE(ta.type_count, 0) - 1, 0)::INTEGER AS extra_type_count,
      COALESCE(ta.type_breakdown, '[]'::JSONB) AS type_breakdown
    FROM public.users u
    JOIN public.assignments_promotor_store aps
      ON aps.promotor_id = u.id
     AND aps.active = true
    JOIN public.stores st
      ON st.id = aps.store_id
    LEFT JOIN promotor_totals pt
      ON pt.promotor_id = u.id
    LEFT JOIN type_agg ta
      ON ta.promotor_id = u.id
    LEFT JOIN LATERAL public.get_daily_target_dashboard(u.id, p_date) dtd
      ON TRUE
    WHERE u.role = 'promotor'
      AND u.deleted_at IS NULL
  )
  SELECT
    ROW_NUMBER() OVER (
      ORDER BY ap.total_bonus DESC, ap.total_sales DESC, ap.promotor_name
    )::INTEGER AS rank,
    ap.promotor_id,
    ap.promotor_name,
    ap.store_name,
    ap.total_sales,
    ap.total_bonus,
    ap.daily_target,
    ap.has_sold,
    ap.primary_type,
    ap.extra_type_count,
    ap.type_breakdown
  FROM all_promotors ap
  ORDER BY ap.total_bonus DESC, ap.total_sales DESC, ap.promotor_name
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_daily_ranking(DATE, UUID, INTEGER) TO authenticated;
