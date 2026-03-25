-- Make leaderboard/feed area handling case-insensitive and resilient to
-- missing/incomplete hierarchy_sator_promotor mappings.
--
-- Goal:
-- - keep live feed scoped by area
-- - keep podium bonus
-- - keep leaderboard grouped per SATOR
-- - still show promotors with sales even when hierarchy mapping is missing
--   by placing them under "Tanpa SATOR"

CREATE OR REPLACE FUNCTION public.get_live_feed(
  p_user_id UUID,
  p_date DATE DEFAULT CURRENT_DATE,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  feed_id UUID,
  feed_type TEXT,
  sale_id UUID,
  promotor_id UUID,
  promotor_name TEXT,
  store_name TEXT,
  product_name TEXT,
  variant_name TEXT,
  price NUMERIC,
  bonus NUMERIC,
  payment_method TEXT,
  leasing_provider TEXT,
  customer_type TEXT,
  notes TEXT,
  image_url TEXT,
  reaction_counts JSONB,
  user_reactions TEXT[],
  comment_count INTEGER,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_role TEXT;
  v_user_area TEXT;
BEGIN
  SELECT u.role, NULLIF(BTRIM(u.area), '')
  INTO v_user_role, v_user_area
  FROM public.users u
  WHERE u.id = p_user_id;

  RETURN QUERY
  WITH sale_bonus AS (
    SELECT
      sbe.sales_sell_out_id,
      COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC AS total_bonus
    FROM public.sales_bonus_events sbe
    GROUP BY sbe.sales_sell_out_id
  )
  SELECT
    so.id AS feed_id,
    'sale'::TEXT AS feed_type,
    so.id AS sale_id,
    u.id AS promotor_id,
    u.full_name AS promotor_name,
    st.store_name,
    (p.series || ' ' || p.model_name) AS product_name,
    (pv.ram_rom || ' ' || pv.color) AS variant_name,
    so.price_at_transaction AS price,
    COALESCE(sb.total_bonus, 0) AS bonus,
    so.payment_method,
    so.leasing_provider,
    so.customer_type::TEXT,
    so.notes,
    so.image_proof_url AS image_url,
    COALESCE(
      (
        SELECT jsonb_object_agg(fr.reaction_type, fr.count)
        FROM (
          SELECT fr.reaction_type, COUNT(*)::INTEGER AS count
          FROM public.feed_reactions fr
          WHERE fr.sale_id = so.id
          GROUP BY fr.reaction_type
        ) fr
      ),
      '{}'::jsonb
    ) AS reaction_counts,
    COALESCE(
      (
        SELECT array_agg(fr.reaction_type)
        FROM public.feed_reactions fr
        WHERE fr.sale_id = so.id AND fr.user_id = p_user_id
      ),
      ARRAY[]::TEXT[]
    ) AS user_reactions,
    COALESCE(
      (
        SELECT COUNT(*)::INTEGER
        FROM public.feed_comments fc
        WHERE fc.sale_id = so.id AND fc.deleted_at IS NULL
      ),
      0
    ) AS comment_count,
    so.created_at
  FROM public.sales_sell_out so
  JOIN public.users u ON u.id = so.promotor_id
  JOIN public.stores st ON st.id = so.store_id
  JOIN public.product_variants pv ON pv.id = so.variant_id
  JOIN public.products p ON p.id = pv.product_id
  LEFT JOIN sale_bonus sb ON sb.sales_sell_out_id = so.id
  WHERE so.transaction_date = p_date
    AND so.deleted_at IS NULL
    AND COALESCE(so.is_chip_sale, false) = false
    AND (
      v_user_role != 'promotor'
      OR LOWER(BTRIM(COALESCE(st.area, ''))) = LOWER(BTRIM(COALESCE(v_user_area, '')))
    )
  ORDER BY so.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

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

    WITH bonus_per_sale AS (
      SELECT
        sbe.sales_sell_out_id,
        COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC AS total_bonus
      FROM public.sales_bonus_events sbe
      GROUP BY sbe.sales_sell_out_id
    ),
    roster AS (
      SELECT
        u.id AS promotor_id,
        u.full_name AS promotor_name,
        COALESCE(u.promotor_type, 'official') AS promotor_type
      FROM public.users u
      WHERE u.role = 'promotor'
        AND LOWER(BTRIM(COALESCE(u.area, ''))) = v_area.area_key
    ),
    top_promotors AS (
      SELECT
        r.promotor_name AS full_name,
        COALESCE(SUM(bps.total_bonus), 0) AS total_bonus
      FROM roster r
      LEFT JOIN public.sales_sell_out s ON s.promotor_id = r.promotor_id
        AND s.transaction_date = p_date
        AND s.deleted_at IS NULL
        AND COALESCE(s.is_chip_sale, false) = false
      LEFT JOIN bonus_per_sale bps ON bps.sales_sell_out_id = s.id
      GROUP BY r.promotor_id, r.promotor_name
      HAVING COALESCE(SUM(bps.total_bonus), 0) > 0
      ORDER BY total_bonus DESC, r.promotor_name
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
      WITH bonus_per_sale AS (
        SELECT
          sbe.sales_sell_out_id,
          COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC AS total_bonus
        FROM public.sales_bonus_events sbe
        GROUP BY sbe.sales_sell_out_id
      ),
      roster AS (
        SELECT
          u.id AS promotor_id,
          u.full_name AS promotor_name,
          COALESCE(u.promotor_type, 'official') AS promotor_type,
          sator.id AS sator_id,
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
      promotor_sales AS (
        SELECT
          r.sator_id,
          r.sator_name,
          r.promotor_id,
          r.promotor_name,
          r.promotor_type,
          COUNT(s.id) AS sale_count,
          COALESCE(SUM(s.price_at_transaction), 0) AS total_revenue,
          COALESCE(SUM(bps.total_bonus), 0) AS total_bonus,
          MIN(st.store_name) FILTER (WHERE st.store_name IS NOT NULL) AS store_name,
          jsonb_agg(
            jsonb_build_object(
              'product_name', p.model_name,
              'variant_name', pv.ram_rom || ' ' || pv.color,
              'price', s.price_at_transaction,
              'bonus', COALESCE(bps.total_bonus, 0),
              'is_chip_sale', s.is_chip_sale,
              'store_name', st.store_name
            )
            ORDER BY s.created_at DESC
          ) AS sales
        FROM roster r
        JOIN public.sales_sell_out s
          ON s.promotor_id = r.promotor_id
         AND s.transaction_date = p_date
         AND s.deleted_at IS NULL
         AND COALESCE(s.is_chip_sale, false) = false
        JOIN public.product_variants pv ON pv.id = s.variant_id
        JOIN public.products p ON p.id = pv.product_id
        LEFT JOIN public.stores st ON st.id = s.store_id
        LEFT JOIN bonus_per_sale bps ON bps.sales_sell_out_id = s.id
        GROUP BY
          r.sator_id,
          r.sator_name,
          r.promotor_id,
          r.promotor_name,
          r.promotor_type
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
          sator.id AS sator_id,
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
      WHERE NOT EXISTS (
        SELECT 1
        FROM public.sales_sell_out s
        WHERE s.promotor_id = r.promotor_id
          AND s.transaction_date = p_date
          AND s.deleted_at IS NULL
          AND COALESCE(s.is_chip_sale, false) = false
      )
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
        COUNT(s.id),
        COALESCE(SUM(s.price_at_transaction), 0)
      INTO v_area_total_sales, v_area_total_revenue
      FROM public.sales_sell_out s
      JOIN public.users u ON u.id = s.promotor_id
      WHERE LOWER(BTRIM(COALESCE(u.area, ''))) = v_area.area_key
        AND s.transaction_date = p_date
        AND s.deleted_at IS NULL
        AND COALESCE(s.is_chip_sale, false) = false;

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

GRANT EXECUTE ON FUNCTION public.get_live_feed(UUID, DATE, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_leaderboard_feed(UUID, DATE) TO authenticated;
