DROP FUNCTION IF EXISTS public.get_spv_sellout_monitor(UUID, TEXT, DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_spv_sellout_monitor(
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
  v_spv_target_all NUMERIC := 0;
  v_spv_target_focus NUMERIC := 0;
  v_spv_target_special NUMERIC := 0;
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
      COALESCE(NULLIF(su.full_name, ''), 'SATOR') AS sator_name
    FROM public.hierarchy_spv_sator hs
    JOIN public.users su ON su.id = hs.sator_id
    WHERE hs.spv_id = p_spv_id
      AND hs.active = true
      AND su.deleted_at IS NULL
  ),
  linked_promotors AS (
    SELECT
      hsp.sator_id,
      hsp.promotor_id,
      COALESCE(NULLIF(pu.nickname, ''), NULLIF(pu.full_name, ''), 'Promotor') AS promotor_name
    FROM public.hierarchy_sator_promotor hsp
    JOIN public.users pu ON pu.id = hsp.promotor_id
    JOIN linked_sators ls ON ls.sator_id = hsp.sator_id
    WHERE hsp.active = true
      AND pu.deleted_at IS NULL
  ),
  latest_assignments AS (
    SELECT DISTINCT ON (aps.promotor_id)
      aps.promotor_id,
      COALESCE(st.store_name, 'Belum ada toko') AS store_name
    FROM public.assignments_promotor_store aps
    LEFT JOIN public.stores st ON st.id = aps.store_id
    WHERE aps.active = true
    ORDER BY aps.promotor_id, aps.created_at DESC
  ),
  sales_flat AS (
    SELECT
      lp.sator_id,
      s.promotor_id,
      pv.product_id,
      COALESCE(s.price_at_transaction, 0)::NUMERIC AS sale_value
    FROM public.sales_sell_out s
    JOIN linked_promotors lp ON lp.promotor_id = s.promotor_id
    JOIN public.product_variants pv ON pv.id = s.variant_id
    WHERE s.deleted_at IS NULL
      AND COALESCE(s.is_chip_sale, false) = false
      AND s.transaction_date BETWEEN v_range_start AND v_range_end
  ),
  target_rows AS (
    SELECT
      ut.user_id,
      COALESCE(ut.target_sell_out, 0)::NUMERIC AS target_sell_out,
      COALESCE(ut.target_fokus_total, 0)::NUMERIC AS target_fokus_total,
      COALESCE(ut.target_fokus, 0)::NUMERIC AS target_fokus_legacy,
      COALESCE(ut.target_special, 0)::NUMERIC AS target_special,
      COALESCE(ut.target_fokus_detail, '{}'::jsonb) AS target_fokus_detail,
      COALESCE(ut.target_special_detail, '{}'::jsonb) AS target_special_detail
    FROM public.user_targets ut
    WHERE ut.period_id = v_period_id
  ),
  sator_targets AS (
    SELECT
      ls.sator_id,
      COALESCE(tr.target_sell_out, 0)::NUMERIC * v_target_ratio AS target_all,
      (
        CASE
          WHEN COALESCE(tr.target_fokus_total, 0) > 0 THEN tr.target_fokus_total
          WHEN COALESCE(tr.target_fokus_legacy, 0) > 0 THEN tr.target_fokus_legacy
          ELSE (
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(COALESCE(tr.target_fokus_detail, '{}'::jsonb))), 0)
            +
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(COALESCE(tr.target_special_detail, '{}'::jsonb))), 0)
          )
        END
      ) * v_target_ratio AS target_focus,
      COALESCE(tr.target_fokus_detail, '{}'::jsonb) AS target_fokus_detail,
      COALESCE(tr.target_special_detail, '{}'::jsonb) AS target_special_detail
    FROM linked_sators ls
    LEFT JOIN target_rows tr ON tr.user_id = ls.sator_id
  ),
  promotor_targets AS (
    SELECT
      lp.sator_id,
      lp.promotor_id,
      lp.promotor_name,
      COALESCE(la.store_name, 'Belum ada toko') AS store_name,
      COALESCE(tr.target_sell_out, 0)::NUMERIC * v_target_ratio AS target_all,
      (
        CASE
          WHEN COALESCE(tr.target_fokus_total, 0) > 0 THEN tr.target_fokus_total
          WHEN COALESCE(tr.target_fokus_legacy, 0) > 0 THEN tr.target_fokus_legacy
          ELSE (
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(COALESCE(tr.target_fokus_detail, '{}'::jsonb))), 0)
            +
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(COALESCE(tr.target_special_detail, '{}'::jsonb))), 0)
          )
        END
      ) * v_target_ratio AS target_focus,
      COALESCE(tr.target_fokus_detail, '{}'::jsonb) AS target_fokus_detail,
      COALESCE(tr.target_special_detail, '{}'::jsonb) AS target_special_detail
    FROM linked_promotors lp
    LEFT JOIN latest_assignments la ON la.promotor_id = lp.promotor_id
    LEFT JOIN target_rows tr ON tr.user_id = lp.promotor_id
  ),
  promotor_metrics AS (
    SELECT
      pt.sator_id,
      pt.promotor_id,
      pt.promotor_name,
      pt.store_name,
      pt.target_all,
      COALESCE((
        SELECT SUM(sf.sale_value)
        FROM sales_flat sf
        WHERE sf.promotor_id = pt.promotor_id
      ), 0)::NUMERIC AS actual_all,
      pt.target_focus,
      COALESCE((
        SELECT COUNT(*)
        FROM sales_flat sf
        JOIN public.products p ON p.id = sf.product_id
        WHERE sf.promotor_id = pt.promotor_id
          AND (
            EXISTS (
              SELECT 1
              FROM public.get_target_focus_product_ids(
                v_period_id,
                pt.target_fokus_detail,
                pt.target_special_detail
              ) tp
              WHERE tp.product_id = sf.product_id
            )
            OR (
              pt.target_fokus_detail = '{}'::jsonb
              AND pt.target_special_detail = '{}'::jsonb
              AND (COALESCE(p.is_focus, false) OR COALESCE(p.is_fokus, false))
            )
          )
      ), 0)::INTEGER AS actual_focus,
      COALESCE((
        SELECT json_agg(
          json_build_object(
            'bundle_id', x.bundle_id,
            'bundle_name', x.bundle_name,
            'target_qty', ROUND(x.target_qty * v_target_ratio, 1),
            'actual_qty', x.actual_qty,
            'achievement_pct', CASE
              WHEN x.target_qty * v_target_ratio > 0
                THEN ROUND((x.actual_qty::NUMERIC / (x.target_qty * v_target_ratio)) * 100, 1)
              ELSE 0
            END
          )
          ORDER BY x.bundle_name
        )
        FROM (
          SELECT
            fb.id::TEXT AS bundle_id,
            fb.bundle_name,
            (d.value::TEXT)::NUMERIC AS target_qty,
            (
              SELECT COUNT(*)
              FROM sales_flat sf
              JOIN public.products p ON p.id = sf.product_id
              WHERE sf.promotor_id = pt.promotor_id
                AND p.model_name = ANY(fb.product_types)
            )::INTEGER AS actual_qty
          FROM jsonb_each(pt.target_fokus_detail) d
          JOIN public.fokus_bundles fb ON fb.id::TEXT = d.key

          UNION ALL

          SELECT
            sb.id::TEXT AS bundle_id,
            sb.bundle_name,
            (d.value::TEXT)::NUMERIC AS target_qty,
            (
              SELECT COUNT(*)
              FROM sales_flat sf
              JOIN public.special_focus_bundle_products sbp
                ON sbp.product_id = sf.product_id
              WHERE sf.promotor_id = pt.promotor_id
                AND sbp.bundle_id = sb.id
            )::INTEGER AS actual_qty
          FROM jsonb_each(pt.target_special_detail) d
          JOIN public.special_focus_bundles sb
            ON sb.id::TEXT = d.key
           AND sb.period_id = v_period_id
        ) x
      ), '[]'::json) AS focus_details
    FROM promotor_targets pt
  ),
  sator_metrics AS (
    SELECT
      ls.sator_id,
      ls.sator_name,
      COALESCE(st.target_all, 0)::NUMERIC AS target_all,
      COALESCE((
        SELECT SUM(sf.sale_value)
        FROM sales_flat sf
        WHERE sf.sator_id = ls.sator_id
      ), 0)::NUMERIC AS actual_all,
      COALESCE(st.target_focus, 0)::NUMERIC AS target_focus,
      COALESCE((
        SELECT COUNT(*)
        FROM sales_flat sf
        JOIN public.products p ON p.id = sf.product_id
        WHERE sf.sator_id = ls.sator_id
          AND (
            EXISTS (
              SELECT 1
              FROM public.get_target_focus_product_ids(
                v_period_id,
                st.target_fokus_detail,
                st.target_special_detail
              ) tp
              WHERE tp.product_id = sf.product_id
            )
            OR (
              st.target_fokus_detail = '{}'::jsonb
              AND st.target_special_detail = '{}'::jsonb
              AND (COALESCE(p.is_focus, false) OR COALESCE(p.is_fokus, false))
            )
          )
      ), 0)::INTEGER AS actual_focus
    FROM linked_sators ls
    LEFT JOIN sator_targets st ON st.sator_id = ls.sator_id
  ),
  summary_base AS (
    SELECT
      COALESCE(SUM(sm.target_all), 0)::NUMERIC AS sator_target_all,
      COALESCE(SUM(sm.actual_all), 0)::NUMERIC AS actual_all,
      COALESCE(SUM(sm.target_focus), 0)::NUMERIC AS sator_target_focus,
      COALESCE(SUM(sm.actual_focus), 0)::NUMERIC AS actual_focus
    FROM sator_metrics sm
  )
  SELECT
    COALESCE(tr.target_sell_out, 0)::NUMERIC * v_target_ratio,
    (
      CASE
        WHEN COALESCE(tr.target_fokus_detail, '{}'::jsonb) <> '{}'::jsonb THEN
          COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(tr.target_fokus_detail)), 0)
        WHEN COALESCE(tr.target_fokus_total, 0) > 0 THEN GREATEST(tr.target_fokus_total - COALESCE(tr.target_special, 0), 0)
        WHEN COALESCE(tr.target_fokus_legacy, 0) > 0 THEN GREATEST(tr.target_fokus_legacy - COALESCE(tr.target_special, 0), 0)
        ELSE 0
      END
    ) * v_target_ratio,
    (
      CASE
        WHEN COALESCE(tr.target_special_detail, '{}'::jsonb) <> '{}'::jsonb THEN
          COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(tr.target_special_detail)), 0)
        ELSE COALESCE(tr.target_special, 0)
      END
    ) * v_target_ratio
  INTO v_spv_target_all, v_spv_target_focus, v_spv_target_special
  FROM target_rows tr
  WHERE tr.user_id = p_spv_id;

  WITH linked_sators AS (
    SELECT
      hs.sator_id,
      COALESCE(NULLIF(su.full_name, ''), 'SATOR') AS sator_name
    FROM public.hierarchy_spv_sator hs
    JOIN public.users su ON su.id = hs.sator_id
    WHERE hs.spv_id = p_spv_id
      AND hs.active = true
      AND su.deleted_at IS NULL
  ),
  linked_promotors AS (
    SELECT
      hsp.sator_id,
      hsp.promotor_id,
      COALESCE(NULLIF(pu.nickname, ''), NULLIF(pu.full_name, ''), 'Promotor') AS promotor_name
    FROM public.hierarchy_sator_promotor hsp
    JOIN public.users pu ON pu.id = hsp.promotor_id
    JOIN linked_sators ls ON ls.sator_id = hsp.sator_id
    WHERE hsp.active = true
      AND pu.deleted_at IS NULL
  ),
  latest_assignments AS (
    SELECT DISTINCT ON (aps.promotor_id)
      aps.promotor_id,
      COALESCE(st.store_name, 'Belum ada toko') AS store_name
    FROM public.assignments_promotor_store aps
    LEFT JOIN public.stores st ON st.id = aps.store_id
    WHERE aps.active = true
    ORDER BY aps.promotor_id, aps.created_at DESC
  ),
  sales_flat AS (
    SELECT
      lp.sator_id,
      s.promotor_id,
      pv.product_id,
      COALESCE(s.price_at_transaction, 0)::NUMERIC AS sale_value
    FROM public.sales_sell_out s
    JOIN linked_promotors lp ON lp.promotor_id = s.promotor_id
    JOIN public.product_variants pv ON pv.id = s.variant_id
    WHERE s.deleted_at IS NULL
      AND COALESCE(s.is_chip_sale, false) = false
      AND s.transaction_date BETWEEN v_range_start AND v_range_end
  ),
  target_rows AS (
    SELECT
      ut.user_id,
      COALESCE(ut.target_sell_out, 0)::NUMERIC AS target_sell_out,
      COALESCE(ut.target_fokus_total, 0)::NUMERIC AS target_fokus_total,
      COALESCE(ut.target_fokus, 0)::NUMERIC AS target_fokus_legacy,
      COALESCE(ut.target_special, 0)::NUMERIC AS target_special,
      COALESCE(ut.target_fokus_detail, '{}'::jsonb) AS target_fokus_detail,
      COALESCE(ut.target_special_detail, '{}'::jsonb) AS target_special_detail
    FROM public.user_targets ut
    WHERE ut.period_id = v_period_id
  ),
  sator_targets AS (
    SELECT
      ls.sator_id,
      COALESCE(tr.target_sell_out, 0)::NUMERIC * v_target_ratio AS target_all,
      (
        CASE
          WHEN COALESCE(tr.target_fokus_detail, '{}'::jsonb) <> '{}'::jsonb THEN
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(tr.target_fokus_detail)), 0)
          WHEN COALESCE(tr.target_fokus_total, 0) > 0 THEN GREATEST(tr.target_fokus_total - COALESCE(tr.target_special, 0), 0)
          WHEN COALESCE(tr.target_fokus_legacy, 0) > 0 THEN GREATEST(tr.target_fokus_legacy - COALESCE(tr.target_special, 0), 0)
          ELSE 0
        END
      ) * v_target_ratio AS target_focus,
      (
        CASE
          WHEN COALESCE(tr.target_special_detail, '{}'::jsonb) <> '{}'::jsonb THEN
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(tr.target_special_detail)), 0)
          ELSE COALESCE(tr.target_special, 0)
        END
      ) * v_target_ratio AS target_special,
      COALESCE(tr.target_fokus_detail, '{}'::jsonb) AS target_fokus_detail,
      COALESCE(tr.target_special_detail, '{}'::jsonb) AS target_special_detail
    FROM linked_sators ls
    LEFT JOIN target_rows tr ON tr.user_id = ls.sator_id
  ),
  promotor_targets AS (
    SELECT
      lp.sator_id,
      lp.promotor_id,
      lp.promotor_name,
      COALESCE(la.store_name, 'Belum ada toko') AS store_name,
      COALESCE(tr.target_sell_out, 0)::NUMERIC * v_target_ratio AS target_all,
      (
        CASE
          WHEN COALESCE(tr.target_fokus_detail, '{}'::jsonb) <> '{}'::jsonb THEN
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(tr.target_fokus_detail)), 0)
          WHEN COALESCE(tr.target_fokus_total, 0) > 0 THEN GREATEST(tr.target_fokus_total - COALESCE(tr.target_special, 0), 0)
          WHEN COALESCE(tr.target_fokus_legacy, 0) > 0 THEN GREATEST(tr.target_fokus_legacy - COALESCE(tr.target_special, 0), 0)
          ELSE 0
        END
      ) * v_target_ratio AS target_focus,
      (
        CASE
          WHEN COALESCE(tr.target_special_detail, '{}'::jsonb) <> '{}'::jsonb THEN
            COALESCE((SELECT SUM((value::text)::NUMERIC) FROM jsonb_each(tr.target_special_detail)), 0)
          ELSE COALESCE(tr.target_special, 0)
        END
      ) * v_target_ratio AS target_special,
      COALESCE(tr.target_fokus_detail, '{}'::jsonb) AS target_fokus_detail,
      COALESCE(tr.target_special_detail, '{}'::jsonb) AS target_special_detail
    FROM linked_promotors lp
    LEFT JOIN latest_assignments la ON la.promotor_id = lp.promotor_id
    LEFT JOIN target_rows tr ON tr.user_id = lp.promotor_id
  ),
  promotor_metrics AS (
    SELECT
      pt.sator_id,
      pt.promotor_id,
      pt.promotor_name,
      pt.store_name,
      json_build_object(
        'target', pt.target_all,
        'actual', COALESCE((
          SELECT SUM(sf.sale_value)
          FROM sales_flat sf
          WHERE sf.promotor_id = pt.promotor_id
        ), 0),
        'achievement_pct', CASE
          WHEN pt.target_all > 0 THEN ROUND((
            COALESCE((SELECT SUM(sf.sale_value) FROM sales_flat sf WHERE sf.promotor_id = pt.promotor_id), 0)
            / pt.target_all
          ) * 100, 1)
          ELSE 0
        END
      ) AS all_type,
      json_build_object(
        'target', pt.target_focus,
        'actual', COALESCE((
          SELECT COUNT(*)
          FROM sales_flat sf
          JOIN public.products p ON p.id = sf.product_id
          WHERE sf.promotor_id = pt.promotor_id
            AND (
              EXISTS (
                SELECT 1
                FROM public.get_target_focus_product_ids(
                  v_period_id,
                  pt.target_fokus_detail,
                  '{}'::jsonb
                ) tp
                WHERE tp.product_id = sf.product_id
              )
              OR (
                pt.target_fokus_detail = '{}'::jsonb
                AND pt.target_special_detail = '{}'::jsonb
                AND (COALESCE(p.is_focus, false) OR COALESCE(p.is_fokus, false))
              )
            )
        ), 0),
        'achievement_pct', CASE
          WHEN pt.target_focus > 0 THEN ROUND((
            COALESCE((
              SELECT COUNT(*)
              FROM sales_flat sf
              JOIN public.products p ON p.id = sf.product_id
              WHERE sf.promotor_id = pt.promotor_id
                AND (
                  EXISTS (
                    SELECT 1
                    FROM public.get_target_focus_product_ids(
                      v_period_id,
                      pt.target_fokus_detail,
                      '{}'::jsonb
                    ) tp
                    WHERE tp.product_id = sf.product_id
                  )
                  OR (
                    pt.target_fokus_detail = '{}'::jsonb
                    AND pt.target_special_detail = '{}'::jsonb
                    AND (COALESCE(p.is_focus, false) OR COALESCE(p.is_fokus, false))
                  )
                )
            ), 0)::NUMERIC / pt.target_focus
          ) * 100, 1)
          ELSE 0
        END,
        'details', COALESCE((
          SELECT json_agg(
            json_build_object(
              'bundle_id', x.bundle_id,
              'bundle_name', x.bundle_name,
              'target_qty', ROUND(x.target_qty * v_target_ratio, 1),
              'actual_qty', x.actual_qty,
              'achievement_pct', CASE
                WHEN x.target_qty * v_target_ratio > 0
                  THEN ROUND((x.actual_qty::NUMERIC / (x.target_qty * v_target_ratio)) * 100, 1)
                ELSE 0
              END
            )
            ORDER BY x.bundle_name
          )
          FROM (
            SELECT
              fb.id::TEXT AS bundle_id,
              fb.bundle_name,
              (d.value::TEXT)::NUMERIC AS target_qty,
              (
                SELECT COUNT(*)
                FROM sales_flat sf
                JOIN public.products p ON p.id = sf.product_id
                WHERE sf.promotor_id = pt.promotor_id
                  AND p.model_name = ANY(fb.product_types)
              )::INTEGER AS actual_qty
            FROM jsonb_each(pt.target_fokus_detail) d
            JOIN public.fokus_bundles fb ON fb.id::TEXT = d.key

            UNION ALL

            SELECT
              sb.id::TEXT AS bundle_id,
              sb.bundle_name,
              (d.value::TEXT)::NUMERIC AS target_qty,
              (
                SELECT COUNT(*)
                FROM sales_flat sf
                JOIN public.special_focus_bundle_products sbp
                  ON sbp.product_id = sf.product_id
                WHERE sf.promotor_id = pt.promotor_id
                  AND sbp.bundle_id = sb.id
              )::INTEGER AS actual_qty
            FROM jsonb_each(pt.target_special_detail) d
            JOIN public.special_focus_bundles sb
              ON sb.id::TEXT = d.key
             AND sb.period_id = v_period_id
          ) x
        ), '[]'::json)
      ) AS focus,
      json_build_object(
        'target', pt.target_special,
        'actual', COALESCE((
          SELECT COUNT(*)
          FROM sales_flat sf
          JOIN public.special_focus_bundle_products sbp
            ON sbp.product_id = sf.product_id
          WHERE sf.promotor_id = pt.promotor_id
            AND EXISTS (
              SELECT 1
              FROM jsonb_each(pt.target_special_detail) d
              WHERE d.key = sbp.bundle_id::TEXT
            )
        ), 0),
        'achievement_pct', CASE
          WHEN pt.target_special > 0 THEN ROUND((
            COALESCE((
              SELECT COUNT(*)
              FROM sales_flat sf
              JOIN public.special_focus_bundle_products sbp
                ON sbp.product_id = sf.product_id
              WHERE sf.promotor_id = pt.promotor_id
                AND EXISTS (
                  SELECT 1
                  FROM jsonb_each(pt.target_special_detail) d
                  WHERE d.key = sbp.bundle_id::TEXT
                )
            ), 0)::NUMERIC / pt.target_special
          ) * 100, 1)
          ELSE 0
        END,
        'details', COALESCE((
          SELECT json_agg(
            json_build_object(
              'bundle_id', sb.id::TEXT,
              'bundle_name', sb.bundle_name,
              'target_qty', ROUND((d.value::TEXT)::NUMERIC * v_target_ratio, 1),
              'actual_qty', (
                SELECT COUNT(*)
                FROM sales_flat sf
                JOIN public.special_focus_bundle_products sbp
                  ON sbp.product_id = sf.product_id
                WHERE sf.promotor_id = pt.promotor_id
                  AND sbp.bundle_id = sb.id
              )::INTEGER,
              'achievement_pct', CASE
                WHEN (d.value::TEXT)::NUMERIC * v_target_ratio > 0 THEN ROUND((
                  (
                    SELECT COUNT(*)
                    FROM sales_flat sf
                    JOIN public.special_focus_bundle_products sbp
                      ON sbp.product_id = sf.product_id
                    WHERE sf.promotor_id = pt.promotor_id
                      AND sbp.bundle_id = sb.id
                  )::NUMERIC / ((d.value::TEXT)::NUMERIC * v_target_ratio)
                ) * 100, 1)
                ELSE 0
              END
            )
            ORDER BY sb.bundle_name
          )
          FROM jsonb_each(pt.target_special_detail) d
          JOIN public.special_focus_bundles sb
            ON sb.id::TEXT = d.key
           AND sb.period_id = v_period_id
        ), '[]'::json)
      ) AS special
    FROM promotor_targets pt
  ),
  sator_metrics AS (
    SELECT
      ls.sator_id,
      ls.sator_name,
      json_build_object(
        'target', COALESCE(st.target_all, 0),
        'actual', COALESCE((SELECT SUM(sf.sale_value) FROM sales_flat sf WHERE sf.sator_id = ls.sator_id), 0),
        'achievement_pct', CASE
          WHEN COALESCE(st.target_all, 0) > 0 THEN ROUND((
            COALESCE((SELECT SUM(sf.sale_value) FROM sales_flat sf WHERE sf.sator_id = ls.sator_id), 0)
            / st.target_all
          ) * 100, 1)
          ELSE 0
        END
      ) AS all_type,
      json_build_object(
        'target', COALESCE(st.target_focus, 0),
        'actual', COALESCE((
          SELECT COUNT(*)
          FROM sales_flat sf
          JOIN public.products p ON p.id = sf.product_id
          WHERE sf.sator_id = ls.sator_id
            AND (
              EXISTS (
                SELECT 1
                FROM public.get_target_focus_product_ids(
                  v_period_id,
                  st.target_fokus_detail,
                  '{}'::jsonb
                ) tp
                WHERE tp.product_id = sf.product_id
              )
              OR (
                st.target_fokus_detail = '{}'::jsonb
                AND st.target_special_detail = '{}'::jsonb
                AND (COALESCE(p.is_focus, false) OR COALESCE(p.is_fokus, false))
              )
            )
        ), 0),
        'achievement_pct', CASE
          WHEN COALESCE(st.target_focus, 0) > 0 THEN ROUND((
            COALESCE((
              SELECT COUNT(*)
              FROM sales_flat sf
              JOIN public.products p ON p.id = sf.product_id
              WHERE sf.sator_id = ls.sator_id
                AND (
                  EXISTS (
                    SELECT 1
                    FROM public.get_target_focus_product_ids(
                      v_period_id,
                      st.target_fokus_detail,
                      '{}'::jsonb
                    ) tp
                    WHERE tp.product_id = sf.product_id
                  )
                  OR (
                    st.target_fokus_detail = '{}'::jsonb
                    AND st.target_special_detail = '{}'::jsonb
                    AND (COALESCE(p.is_focus, false) OR COALESCE(p.is_fokus, false))
                  )
                )
            ), 0)::NUMERIC / st.target_focus
          ) * 100, 1)
          ELSE 0
        END
      ) AS focus,
      json_build_object(
        'target', COALESCE(st.target_special, 0),
        'actual', COALESCE((
          SELECT COUNT(*)
          FROM sales_flat sf
          JOIN public.special_focus_bundle_products sbp
            ON sbp.product_id = sf.product_id
          WHERE sf.sator_id = ls.sator_id
            AND EXISTS (
              SELECT 1
              FROM jsonb_each(st.target_special_detail) d
              WHERE d.key = sbp.bundle_id::TEXT
            )
        ), 0),
        'achievement_pct', CASE
          WHEN COALESCE(st.target_special, 0) > 0 THEN ROUND((
            COALESCE((
              SELECT COUNT(*)
              FROM sales_flat sf
              JOIN public.special_focus_bundle_products sbp
                ON sbp.product_id = sf.product_id
              WHERE sf.sator_id = ls.sator_id
                AND EXISTS (
                  SELECT 1
                  FROM jsonb_each(st.target_special_detail) d
                  WHERE d.key = sbp.bundle_id::TEXT
                )
            ), 0)::NUMERIC / st.target_special
          ) * 100, 1)
          ELSE 0
        END
      ) AS special
    FROM linked_sators ls
    LEFT JOIN sator_targets st ON st.sator_id = ls.sator_id
  ),
  summary_base AS (
    SELECT
      COALESCE(SUM((sm.all_type->>'target')::NUMERIC), 0)::NUMERIC AS sator_target_all,
      COALESCE(SUM((sm.all_type->>'actual')::NUMERIC), 0)::NUMERIC AS actual_all,
      COALESCE(SUM((sm.focus->>'target')::NUMERIC), 0)::NUMERIC AS sator_target_focus,
      COALESCE(SUM((sm.focus->>'actual')::NUMERIC), 0)::NUMERIC AS actual_focus,
      COALESCE(SUM((sm.special->>'target')::NUMERIC), 0)::NUMERIC AS sator_target_special,
      COALESCE(SUM((sm.special->>'actual')::NUMERIC), 0)::NUMERIC AS actual_special
    FROM sator_metrics sm
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
        'all_type', json_build_object(
          'target', CASE WHEN COALESCE(v_spv_target_all, 0) > 0 THEN v_spv_target_all ELSE sb.sator_target_all END,
          'actual', sb.actual_all,
          'achievement_pct', CASE
            WHEN (CASE WHEN COALESCE(v_spv_target_all, 0) > 0 THEN v_spv_target_all ELSE sb.sator_target_all END) > 0
              THEN ROUND((sb.actual_all / (CASE WHEN COALESCE(v_spv_target_all, 0) > 0 THEN v_spv_target_all ELSE sb.sator_target_all END)) * 100, 1)
            ELSE 0
          END
        ),
        'focus', json_build_object(
          'target', CASE WHEN COALESCE(v_spv_target_focus, 0) > 0 THEN v_spv_target_focus ELSE sb.sator_target_focus END,
          'actual', sb.actual_focus,
          'achievement_pct', CASE
            WHEN (CASE WHEN COALESCE(v_spv_target_focus, 0) > 0 THEN v_spv_target_focus ELSE sb.sator_target_focus END) > 0
              THEN ROUND((sb.actual_focus / (CASE WHEN COALESCE(v_spv_target_focus, 0) > 0 THEN v_spv_target_focus ELSE sb.sator_target_focus END)) * 100, 1)
            ELSE 0
          END
        )
      )
      FROM summary_base sb
    ),
    'sators', COALESCE((
      SELECT json_agg(
        json_build_object(
          'sator_id', sm.sator_id,
          'sator_name', sm.sator_name,
          'all_type', sm.all_type,
          'focus', sm.focus,
          'promotors', COALESCE((
            SELECT json_agg(
              json_build_object(
                'promotor_id', pm.promotor_id,
                'promotor_name', pm.promotor_name,
                'store_name', pm.store_name,
                'all_type', pm.all_type,
                'focus', pm.focus
              )
              ORDER BY
                COALESCE((pm.all_type->>'achievement_pct')::NUMERIC, 0) DESC,
                COALESCE((pm.focus->>'achievement_pct')::NUMERIC, 0) DESC,
                pm.promotor_name
            )
            FROM promotor_metrics pm
            WHERE pm.sator_id = sm.sator_id
          ), '[]'::json)
        )
        ORDER BY
          COALESCE((sm.all_type->>'achievement_pct')::NUMERIC, 0) DESC,
          COALESCE((sm.focus->>'achievement_pct')::NUMERIC, 0) DESC,
          sm.sator_name
      )
      FROM sator_metrics sm
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
        'all_type', json_build_object('target', 0, 'actual', 0, 'achievement_pct', 0),
        'focus', json_build_object('target', 0, 'actual', 0, 'achievement_pct', 0)
      ),
      'sators', '[]'::json
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_spv_sellout_monitor(UUID, TEXT, DATE, DATE) TO authenticated;
