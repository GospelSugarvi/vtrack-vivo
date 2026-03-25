-- Fix promotor leaderboard/feed to use:
-- 1) transaction_date as the date source of truth
-- 2) event-based bonus from sales_bonus_events
-- This aligns leaderboard/feed with daily dashboard logic.

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
  SELECT u.role, u.area INTO v_user_role, v_user_area
  FROM users u
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
          FROM feed_reactions fr
          WHERE fr.sale_id = so.id
          GROUP BY fr.reaction_type
        ) fr
      ),
      '{}'::jsonb
    ) AS reaction_counts,
    COALESCE(
      (
        SELECT array_agg(fr.reaction_type)
        FROM feed_reactions fr
        WHERE fr.sale_id = so.id AND fr.user_id = p_user_id
      ),
      ARRAY[]::TEXT[]
    ) AS user_reactions,
    COALESCE(
      (
        SELECT COUNT(*)::INTEGER
        FROM feed_comments fc
        WHERE fc.sale_id = so.id AND fc.deleted_at IS NULL
      ),
      0
    ) AS comment_count,
    so.created_at
  FROM sales_sell_out so
  JOIN users u ON u.id = so.promotor_id
  JOIN stores st ON st.id = so.store_id
  JOIN product_variants pv ON pv.id = so.variant_id
  JOIN products p ON p.id = pv.product_id
  LEFT JOIN sale_bonus sb ON sb.sales_sell_out_id = so.id
  WHERE so.transaction_date = p_date
    AND so.deleted_at IS NULL
    AND COALESCE(so.is_chip_sale, false) = false
    AND (v_user_role != 'promotor' OR st.area = v_user_area)
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
  v_user_area TEXT;
  v_result JSONB := '[]'::JSONB;
  v_area TEXT;
  v_top_bonus JSONB;
  v_sales_by_sator RECORD;
  v_no_sales_by_sator RECORD;
BEGIN
  SELECT role, area INTO v_user_role, v_user_area
  FROM users
  WHERE id = p_user_id;

  FOR v_area IN
    SELECT DISTINCT u.area
    FROM users u
    WHERE u.role IN ('promotor', 'sator', 'spv')
      AND (v_user_role = 'admin' OR u.area = v_user_area)
      AND u.area IS NOT NULL
    ORDER BY u.area
  LOOP
    DECLARE v_spv_name TEXT;
    BEGIN
      SELECT full_name INTO v_spv_name
      FROM users
      WHERE role = 'spv' AND area = v_area
      LIMIT 1;

      v_result := v_result || jsonb_build_object(
        'feed_type', 'area_header',
        'area_name', v_area,
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
    top_promotors AS (
      SELECT
        u.full_name,
        COALESCE(SUM(bps.total_bonus), 0) AS total_bonus
      FROM users u
      LEFT JOIN sales_sell_out s ON s.promotor_id = u.id
        AND s.transaction_date = p_date
        AND COALESCE(s.is_chip_sale, false) = false
      LEFT JOIN bonus_per_sale bps ON bps.sales_sell_out_id = s.id
      WHERE u.area = v_area
        AND u.role = 'promotor'
      GROUP BY u.id, u.full_name
      HAVING COALESCE(SUM(bps.total_bonus), 0) > 0
      ORDER BY total_bonus DESC
      LIMIT 3
    )
    SELECT jsonb_agg(
      jsonb_build_object(
        'name', full_name,
        'total_bonus', total_bonus
      ) ORDER BY total_bonus DESC
    )
    INTO v_top_bonus
    FROM top_promotors;

    IF v_top_bonus IS NOT NULL AND jsonb_array_length(v_top_bonus) > 0 THEN
      v_result := v_result || jsonb_build_object(
        'feed_type', 'top_bonus',
        'area_name', v_area,
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
      sator_sales AS (
        SELECT
          sator.id AS sator_id,
          sator.full_name AS sator_name,
          u.id AS promotor_id,
          u.full_name AS promotor_name,
          COALESCE(u.promotor_type, 'official') AS promotor_type
        FROM users sator
        INNER JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = sator.id AND hsp.active = true
        INNER JOIN users u ON u.id = hsp.promotor_id
        WHERE sator.area = v_area
          AND sator.role = 'sator'
          AND u.role = 'promotor'
          AND EXISTS (
            SELECT 1
            FROM sales_sell_out s
            WHERE s.promotor_id = u.id
              AND s.transaction_date = p_date
              AND COALESCE(s.is_chip_sale, false) = false
          )
      )
      SELECT
        ss.sator_id,
        ss.sator_name,
        COUNT(DISTINCT ss.promotor_id) AS promotor_count,
        (
          SELECT COUNT(*)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND s.transaction_date = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        ) AS total_sales,
        (
          SELECT COALESCE(SUM(s.price_at_transaction), 0)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND s.transaction_date = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        ) AS total_revenue,
        (
          SELECT COALESCE(SUM(bps.total_bonus), 0)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          LEFT JOIN bonus_per_sale bps ON bps.sales_sell_out_id = s.id
          WHERE ss2.sator_id = ss.sator_id
            AND s.transaction_date = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        ) AS total_bonus,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', ss.promotor_id,
            'promotor_name', ss.promotor_name,
            'promotor_type', ss.promotor_type,
            'sales', (
              SELECT jsonb_agg(
                jsonb_build_object(
                  'product_name', p.model_name,
                  'variant_name', pv.ram_rom || ' ' || pv.color,
                  'price', s.price_at_transaction,
                  'bonus', COALESCE(bps.total_bonus, 0),
                  'is_chip_sale', s.is_chip_sale
                ) ORDER BY s.created_at DESC
              )
              FROM sales_sell_out s
              JOIN product_variants pv ON pv.id = s.variant_id
              JOIN products p ON p.id = pv.product_id
              LEFT JOIN bonus_per_sale bps ON bps.sales_sell_out_id = s.id
              WHERE s.promotor_id = ss.promotor_id
                AND s.transaction_date = p_date
                AND COALESCE(s.is_chip_sale, false) = false
            )
          ) ORDER BY ss.promotor_name
        ) AS sales_list
      FROM sator_sales ss
      GROUP BY ss.sator_id, ss.sator_name
      ORDER BY ss.sator_name
    LOOP
      v_result := v_result || jsonb_build_object(
        'feed_type', 'sales_list',
        'area_name', v_area,
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
      SELECT
        sator.id AS sator_id,
        sator.full_name AS sator_name,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', u.id,
            'promotor_name', u.full_name,
            'promotor_type', COALESCE(u.promotor_type, 'official')
          ) ORDER BY u.full_name
        ) AS no_sales_list
      FROM users sator
      INNER JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = sator.id AND hsp.active = true
      INNER JOIN users u ON u.id = hsp.promotor_id
      WHERE sator.area = v_area
        AND sator.role = 'sator'
        AND u.role = 'promotor'
        AND NOT EXISTS (
          SELECT 1
          FROM sales_sell_out s
          WHERE s.promotor_id = u.id
            AND s.transaction_date = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        )
      GROUP BY sator.id, sator.full_name
      HAVING COUNT(u.id) > 0
      ORDER BY sator.full_name
    LOOP
      v_result := v_result || jsonb_build_object(
        'feed_type', 'no_sales',
        'area_name', v_area,
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
      FROM sales_sell_out s
      JOIN users u ON u.id = s.promotor_id
      WHERE u.area = v_area
        AND s.transaction_date = p_date
        AND COALESCE(s.is_chip_sale, false) = false;

      IF v_area_total_sales > 0 THEN
        v_result := v_result || jsonb_build_object(
          'feed_type', 'area_summary',
          'area_name', v_area,
          'total_sales', v_area_total_sales,
          'total_revenue', v_area_total_revenue
        );
      END IF;
    END;
  END LOOP;

  RETURN v_result;
END;
$$;
