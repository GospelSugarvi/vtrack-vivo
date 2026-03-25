-- Rebuild leaderboard from the same daily transaction source as live feed.
-- Hierarchy is only used for SATOR grouping / no-sales roster enrichment.

CREATE OR REPLACE FUNCTION public.get_leaderboard_feed(
  p_user_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_role TEXT;
  v_user_area_key TEXT;
  v_result JSONB := '[]'::JSONB;
  v_area RECORD;
  v_top_bonus JSONB;
  v_sales_by_sator RECORD;
  v_no_sales_by_sator RECORD;
BEGIN
  SELECT
    u.role,
    LOWER(NULLIF(BTRIM(u.area), ''))
  INTO v_user_role, v_user_area_key
  FROM public.users u
  WHERE u.id = p_user_id;

  FOR v_area IN
    SELECT
      LOWER(BTRIM(u.area)) AS area_key,
      COALESCE(
        MIN(NULLIF(BTRIM(u.area), '')),
        INITCAP(LOWER(BTRIM(u.area)))
      ) AS area_name
    FROM public.users u
    WHERE u.role IN ('promotor', 'sator', 'spv')
      AND NULLIF(BTRIM(u.area), '') IS NOT NULL
      AND (
        v_user_role = 'admin'
        OR LOWER(BTRIM(u.area)) = v_user_area_key
      )
    GROUP BY LOWER(BTRIM(u.area))
    ORDER BY COALESCE(
      MIN(NULLIF(BTRIM(u.area), '')),
      INITCAP(LOWER(BTRIM(u.area)))
    )
  LOOP
    DECLARE v_spv_name TEXT;
    BEGIN
      SELECT spv.full_name
      INTO v_spv_name
      FROM public.users spv
      WHERE spv.role = 'spv'
        AND LOWER(BTRIM(COALESCE(spv.area, ''))) = v_area.area_key
      ORDER BY spv.full_name
      LIMIT 1;

      v_result := v_result || jsonb_build_object(
        'feed_type', 'area_header',
        'area_name', v_area.area_name,
        'spv_name', COALESCE(v_spv_name, 'Tidak ada SPV')
      );
    END;

    WITH daily_sales AS (
      SELECT
        so.id AS sale_id,
        so.promotor_id,
        u.full_name AS promotor_name,
        COALESCE(u.promotor_type, 'official') AS promotor_type,
        LOWER(
          BTRIM(
            COALESCE(
              NULLIF(u.area, ''),
              NULLIF(st.area, '')
            )
          )
        ) AS area_key,
        st.store_name,
        p.model_name AS product_name,
        (pv.ram_rom || ' ' || pv.color) AS variant_name,
        so.price_at_transaction AS price,
        COALESCE(bps.total_bonus, 0)::NUMERIC AS bonus,
        so.created_at
      FROM public.sales_sell_out so
      JOIN public.users u ON u.id = so.promotor_id
      LEFT JOIN public.stores st ON st.id = so.store_id
      JOIN public.product_variants pv ON pv.id = so.variant_id
      JOIN public.products p ON p.id = pv.product_id
      LEFT JOIN (
        SELECT
          sbe.sales_sell_out_id,
          COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC AS total_bonus
        FROM public.sales_bonus_events sbe
        GROUP BY sbe.sales_sell_out_id
      ) bps ON bps.sales_sell_out_id = so.id
      WHERE so.transaction_date = p_date
        AND so.deleted_at IS NULL
        AND COALESCE(so.is_chip_sale, false) = false
        AND (
          v_user_role = 'admin'
          OR LOWER(
            BTRIM(
              COALESCE(
                NULLIF(u.area, ''),
                NULLIF(st.area, '')
              )
            )
          ) = v_user_area_key
        )
    ),
    top_promotors AS (
      SELECT
        ds.promotor_name AS full_name,
        COALESCE(SUM(ds.bonus), 0) AS total_bonus
      FROM daily_sales ds
      WHERE ds.area_key = v_area.area_key
      GROUP BY ds.promotor_id, ds.promotor_name
      HAVING COALESCE(SUM(ds.bonus), 0) > 0
      ORDER BY total_bonus DESC, ds.promotor_name
      LIMIT 3
    )
    SELECT jsonb_agg(
      jsonb_build_object(
        'name', full_name,
        'total_bonus', total_bonus
      ) ORDER BY total_bonus DESC, full_name
    )
    INTO v_top_bonus
    FROM top_promotors;

    IF v_top_bonus IS NOT NULL AND jsonb_array_length(v_top_bonus) > 0 THEN
      v_result := v_result || jsonb_build_object(
        'feed_type', 'top_bonus',
        'area_name', v_area.area_name,
        'top_bonus_list', v_top_bonus
      );
    END IF;

    FOR v_sales_by_sator IN
      WITH daily_sales AS (
        SELECT
          so.id AS sale_id,
          so.promotor_id,
          u.full_name AS promotor_name,
          COALESCE(u.promotor_type, 'official') AS promotor_type,
          LOWER(
            BTRIM(
              COALESCE(
                NULLIF(u.area, ''),
                NULLIF(st.area, '')
              )
            )
          ) AS area_key,
          st.store_name,
          p.model_name AS product_name,
          (pv.ram_rom || ' ' || pv.color) AS variant_name,
          so.price_at_transaction AS price,
          COALESCE(bps.total_bonus, 0)::NUMERIC AS bonus,
          so.created_at
        FROM public.sales_sell_out so
        JOIN public.users u ON u.id = so.promotor_id
        LEFT JOIN public.stores st ON st.id = so.store_id
        JOIN public.product_variants pv ON pv.id = so.variant_id
        JOIN public.products p ON p.id = pv.product_id
        LEFT JOIN (
          SELECT
            sbe.sales_sell_out_id,
            COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC AS total_bonus
          FROM public.sales_bonus_events sbe
          GROUP BY sbe.sales_sell_out_id
        ) bps ON bps.sales_sell_out_id = so.id
        WHERE so.transaction_date = p_date
          AND so.deleted_at IS NULL
          AND COALESCE(so.is_chip_sale, false) = false
          AND (
            v_user_role = 'admin'
            OR LOWER(
              BTRIM(
                COALESCE(
                  NULLIF(u.area, ''),
                  NULLIF(st.area, '')
                )
              )
            ) = v_user_area_key
          )
      ),
      promotor_sales AS (
        SELECT
          chosen_hsp.sator_id,
          COALESCE(sator.full_name, 'Tanpa SATOR') AS sator_name,
          ds.promotor_id,
          ds.promotor_name,
          ds.promotor_type,
          MIN(ds.store_name) FILTER (WHERE ds.store_name IS NOT NULL) AS store_name,
          COUNT(*) AS sale_count,
          COALESCE(SUM(ds.price), 0) AS total_revenue,
          COALESCE(SUM(ds.bonus), 0) AS total_bonus,
          jsonb_agg(
            jsonb_build_object(
              'product_name', ds.product_name,
              'variant_name', ds.variant_name,
              'price', ds.price,
              'bonus', ds.bonus,
              'is_chip_sale', false,
              'store_name', ds.store_name
            )
            ORDER BY ds.created_at DESC
          ) AS sales
        FROM daily_sales ds
        LEFT JOIN LATERAL (
          SELECT hsp.sator_id
          FROM public.hierarchy_sator_promotor hsp
          JOIN public.users s
            ON s.id = hsp.sator_id
           AND s.role = 'sator'
          WHERE hsp.promotor_id = ds.promotor_id
            AND hsp.active = true
          ORDER BY hsp.created_at DESC, hsp.sator_id
          LIMIT 1
        ) chosen_hsp ON true
        LEFT JOIN public.users sator ON sator.id = chosen_hsp.sator_id
        WHERE ds.area_key = v_area.area_key
        GROUP BY
          chosen_hsp.sator_id,
          sator.full_name,
          ds.promotor_id,
          ds.promotor_name,
          ds.promotor_type
      )
      SELECT
        ps.sator_id,
        ps.sator_name,
        COUNT(*) AS promotor_count,
        COALESCE(SUM(ps.sale_count), 0) AS total_sales,
        COALESCE(SUM(ps.total_revenue), 0) AS total_revenue,
        COALESCE(SUM(ps.total_bonus), 0) AS total_bonus,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', ps.promotor_id,
            'promotor_name', ps.promotor_name,
            'promotor_type', ps.promotor_type,
            'store_name', ps.store_name,
            'is_my_sale', ps.promotor_id = p_user_id,
            'sales', ps.sales
          )
          ORDER BY ps.total_bonus DESC, ps.promotor_name
        ) AS sales_list
      FROM promotor_sales ps
      GROUP BY ps.sator_id, ps.sator_name
      ORDER BY ps.sator_name
    LOOP
      v_result := v_result || jsonb_build_object(
        'feed_type', 'sales_list',
        'area_name', v_area.area_name,
        'sator_id', v_sales_by_sator.sator_id,
        'sator_name', v_sales_by_sator.sator_name,
        'promotor_count', v_sales_by_sator.promotor_count,
        'total_sales', v_sales_by_sator.total_sales,
        'total_revenue', v_sales_by_sator.total_revenue,
        'total_bonus', v_sales_by_sator.total_bonus,
        'sales_list', v_sales_by_sator.sales_list
      );
    END LOOP;

    FOR v_no_sales_by_sator IN
      WITH roster AS (
        SELECT
          u.id AS promotor_id,
          u.full_name AS promotor_name,
          COALESCE(u.promotor_type, 'official') AS promotor_type,
          chosen_hsp.sator_id,
          COALESCE(sator.full_name, 'Tanpa SATOR') AS sator_name
        FROM public.users u
        LEFT JOIN LATERAL (
          SELECT hsp.sator_id
          FROM public.hierarchy_sator_promotor hsp
          JOIN public.users s
            ON s.id = hsp.sator_id
           AND s.role = 'sator'
          WHERE hsp.promotor_id = u.id
            AND hsp.active = true
          ORDER BY hsp.created_at DESC, hsp.sator_id
          LIMIT 1
        ) chosen_hsp ON true
        LEFT JOIN public.users sator ON sator.id = chosen_hsp.sator_id
        WHERE u.role = 'promotor'
          AND LOWER(BTRIM(COALESCE(u.area, ''))) = v_area.area_key
      ),
      sold_promotors AS (
        SELECT DISTINCT so.promotor_id
        FROM public.sales_sell_out so
        JOIN public.users u ON u.id = so.promotor_id
        LEFT JOIN public.stores st ON st.id = so.store_id
        WHERE so.transaction_date = p_date
          AND so.deleted_at IS NULL
          AND COALESCE(so.is_chip_sale, false) = false
          AND LOWER(
            BTRIM(
              COALESCE(
                NULLIF(u.area, ''),
                NULLIF(st.area, '')
              )
            )
          ) = v_area.area_key
      )
      SELECT
        r.sator_id,
        r.sator_name,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', r.promotor_id,
            'promotor_name', r.promotor_name,
            'promotor_type', r.promotor_type,
            'is_my_sale', r.promotor_id = p_user_id
          )
          ORDER BY r.promotor_name
        ) AS no_sales_list
      FROM roster r
      LEFT JOIN sold_promotors sp ON sp.promotor_id = r.promotor_id
      WHERE sp.promotor_id IS NULL
      GROUP BY r.sator_id, r.sator_name
      ORDER BY r.sator_name
    LOOP
      v_result := v_result || jsonb_build_object(
        'feed_type', 'no_sales',
        'area_name', v_area.area_name,
        'sator_id', v_no_sales_by_sator.sator_id,
        'sator_name', v_no_sales_by_sator.sator_name,
        'no_sales_list', v_no_sales_by_sator.no_sales_list
      );
    END LOOP;

    DECLARE
      v_area_total_sales INT;
      v_area_total_revenue NUMERIC;
    BEGIN
      SELECT
        COUNT(*),
        COALESCE(SUM(ds.price), 0)
      INTO v_area_total_sales, v_area_total_revenue
      FROM (
        SELECT
          so.id,
          so.price_at_transaction AS price,
          LOWER(
            BTRIM(
              COALESCE(
                NULLIF(u.area, ''),
                NULLIF(st.area, '')
              )
            )
          ) AS area_key
        FROM public.sales_sell_out so
        JOIN public.users u ON u.id = so.promotor_id
        LEFT JOIN public.stores st ON st.id = so.store_id
        WHERE so.transaction_date = p_date
          AND so.deleted_at IS NULL
          AND COALESCE(so.is_chip_sale, false) = false
      ) ds
      WHERE ds.area_key = v_area.area_key;

      IF v_area_total_sales > 0 THEN
        v_result := v_result || jsonb_build_object(
          'feed_type', 'area_summary',
          'area_name', v_area.area_name,
          'total_sales', v_area_total_sales,
          'total_revenue', v_area_total_revenue
        );
      END IF;
    END;
  END LOOP;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard_feed(UUID, DATE) TO authenticated;
