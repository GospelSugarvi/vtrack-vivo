-- Exclude chip sales from bonus, leaderboard, and bonus summary calculations.
-- Date: 2026-03-09

-- 1. Bonus trigger: chip sale always gets 0 bonus.
CREATE OR REPLACE FUNCTION public.process_sell_out_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_bonus NUMERIC := 0;
  v_period_id UUID;
  v_is_focus BOOLEAN;
  v_promotor_type TEXT;
  v_product_id UUID;
  v_ratio_value INTEGER;
  v_current_sales_count INTEGER;
  v_start_of_month TIMESTAMP;
BEGIN
  SELECT id INTO v_period_id
  FROM target_periods
  WHERE start_date <= NEW.transaction_date
    AND end_date >= NEW.transaction_date
  LIMIT 1;

  SELECT p.is_focus, p.id
  INTO v_is_focus, v_product_id
  FROM products p
  JOIN product_variants pv ON p.id = pv.product_id
  WHERE pv.id = NEW.variant_id;

  SELECT COALESCE(promotor_type, 'official')
  INTO v_promotor_type
  FROM users
  WHERE id = NEW.promotor_id;

  IF COALESCE(NEW.is_chip_sale, false) THEN
    v_bonus := 0;
  ELSE
    SELECT
      CASE
        WHEN v_promotor_type = 'official' THEN COALESCE(bonus_official, flat_bonus)
        ELSE COALESCE(bonus_training, flat_bonus)
      END
    INTO v_bonus
    FROM bonus_rules
    WHERE bonus_type = 'flat'
      AND product_id = v_product_id
    LIMIT 1;

    IF NOT FOUND OR v_bonus IS NULL THEN
      SELECT
        ratio_value,
        CASE
          WHEN v_promotor_type = 'official' THEN bonus_official
          ELSE bonus_training
        END
      INTO v_ratio_value, v_bonus
      FROM bonus_rules
      WHERE bonus_type = 'ratio'
        AND product_id = v_product_id
      LIMIT 1;

      IF FOUND THEN
        v_start_of_month := date_trunc('month', NEW.transaction_date);

        SELECT COUNT(*)
        INTO v_current_sales_count
        FROM sales_sell_out s
        JOIN product_variants pv ON s.variant_id = pv.id
        WHERE s.promotor_id = NEW.promotor_id
          AND COALESCE(s.is_chip_sale, false) = false
          AND pv.product_id = v_product_id
          AND s.transaction_date >= v_start_of_month
          AND s.transaction_date < (v_start_of_month + interval '1 month');

        v_ratio_value := COALESCE(v_ratio_value, 2);
        IF ((v_current_sales_count + 1) % v_ratio_value) != 0 THEN
          v_bonus := 0;
        END IF;
      ELSE
        SELECT
          CASE
            WHEN v_promotor_type = 'official' THEN bonus_official
            ELSE bonus_training
          END
        INTO v_bonus
        FROM bonus_rules
        WHERE bonus_type = 'range'
          AND NEW.price_at_transaction >= min_price
          AND NEW.price_at_transaction < COALESCE(max_price, 999999999)
        LIMIT 1;
      END IF;
    END IF;
  END IF;

  v_bonus := COALESCE(v_bonus, 0);
  NEW.estimated_bonus := v_bonus;

  UPDATE store_inventory
  SET quantity = GREATEST(quantity - 1, 0),
      last_updated = NOW()
  WHERE store_id = NEW.store_id
    AND variant_id = NEW.variant_id;

  IF v_period_id IS NOT NULL THEN
    INSERT INTO dashboard_performance_metrics (
      user_id,
      period_id,
      total_omzet_real,
      total_units_sold,
      total_units_focus,
      estimated_bonus_total
    )
    VALUES (
      NEW.promotor_id,
      v_period_id,
      NEW.price_at_transaction,
      CASE WHEN COALESCE(NEW.is_chip_sale, false) THEN 0 ELSE 1 END,
      CASE WHEN v_is_focus AND COALESCE(NEW.is_chip_sale, false) = false THEN 1 ELSE 0 END,
      v_bonus
    )
    ON CONFLICT (user_id, period_id) DO UPDATE SET
      total_omzet_real = dashboard_performance_metrics.total_omzet_real + EXCLUDED.total_omzet_real,
      total_units_sold = dashboard_performance_metrics.total_units_sold + EXCLUDED.total_units_sold,
      total_units_focus = dashboard_performance_metrics.total_units_focus + EXCLUDED.total_units_focus,
      estimated_bonus_total = dashboard_performance_metrics.estimated_bonus_total + EXCLUDED.estimated_bonus_total,
      last_updated = NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_sell_out_process ON public.sales_sell_out;
CREATE TRIGGER trigger_sell_out_process
BEFORE INSERT ON public.sales_sell_out
FOR EACH ROW
EXECUTE FUNCTION public.process_sell_out_insert();

-- 2. Promotor bonus summary must ignore chip sales.
CREATE OR REPLACE FUNCTION public.get_promotor_bonus_summary(
    p_promotor_id UUID,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_summary JSON;
    v_promotor_type TEXT;
BEGIN
    v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_end_date := COALESCE(p_end_date, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE);

    SELECT COALESCE(promotor_type, 'official')
    INTO v_promotor_type
    FROM users
    WHERE id = p_promotor_id;

    SELECT json_build_object(
        'total_sales', COUNT(*),
        'total_revenue', SUM(so.price_at_transaction),
        'total_bonus', SUM(so.estimated_bonus),
        'promotor_type', v_promotor_type,
        'period_start', v_start_date,
        'period_end', v_end_date,
        'breakdown_by_range', (
            SELECT json_object_agg(price_range, range_data)
            FROM (
                SELECT
                    CASE
                        WHEN so.price_at_transaction < 2000000 THEN 'under_2m'
                        WHEN so.price_at_transaction >= 2000000 AND so.price_at_transaction < 3000000 THEN '2m_3m'
                        WHEN so.price_at_transaction >= 3000000 AND so.price_at_transaction < 4000000 THEN '3m_4m'
                        WHEN so.price_at_transaction >= 4000000 AND so.price_at_transaction < 5000000 THEN '4m_5m'
                        WHEN so.price_at_transaction >= 5000000 AND so.price_at_transaction < 6000000 THEN '5m_6m'
                        ELSE 'above_6m'
                    END as price_range,
                    json_build_object(
                        'count', COUNT(*),
                        'total_bonus', SUM(so.estimated_bonus)
                    ) as range_data
                FROM sales_sell_out so
                WHERE so.promotor_id = p_promotor_id
                  AND so.transaction_date BETWEEN v_start_date AND v_end_date
                  AND COALESCE(so.is_chip_sale, false) = false
                GROUP BY price_range
            ) breakdown
        )
    ) INTO v_summary
    FROM sales_sell_out so
    WHERE so.promotor_id = p_promotor_id
      AND so.transaction_date BETWEEN v_start_date AND v_end_date
      AND COALESCE(so.is_chip_sale, false) = false;

    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_promotor_bonus_details(
    p_promotor_id UUID,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    transaction_id UUID,
    transaction_date DATE,
    product_name TEXT,
    variant_name TEXT,
    price NUMERIC,
    bonus_amount NUMERIC,
    payment_method TEXT,
    leasing_provider TEXT
) AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_end_date := COALESCE(p_end_date, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE);

    RETURN QUERY
    SELECT
        so.id as transaction_id,
        so.transaction_date,
        (p.series || ' ' || p.model_name) as product_name,
        pv.ram_rom || ' ' || pv.color as variant_name,
        so.price_at_transaction as price,
        so.estimated_bonus as bonus_amount,
        so.payment_method,
        so.leasing_provider
    FROM sales_sell_out so
    JOIN product_variants pv ON pv.id = so.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE so.promotor_id = p_promotor_id
      AND so.transaction_date BETWEEN v_start_date AND v_end_date
      AND COALESCE(so.is_chip_sale, false) = false
    ORDER BY so.transaction_date DESC, so.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Leaderboard/feed RPCs must ignore chip sales.
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

    WITH top_promotors AS (
      SELECT
        u.full_name,
        COALESCE(SUM(s.estimated_bonus), 0) as total_bonus
      FROM users u
      LEFT JOIN sales_sell_out s ON s.promotor_id = u.id
        AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
        AND COALESCE(s.is_chip_sale, false) = false
      WHERE u.area = v_area
        AND u.role = 'promotor'
      GROUP BY u.id, u.full_name
      HAVING COALESCE(SUM(s.estimated_bonus), 0) > 0
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
      WITH sator_sales AS (
        SELECT
          sator.id as sator_id,
          sator.full_name as sator_name,
          u.id as promotor_id,
          u.full_name as promotor_name,
          COALESCE(u.promotor_type, 'official') as promotor_type
        FROM users sator
        INNER JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = sator.id AND hsp.active = true
        INNER JOIN users u ON u.id = hsp.promotor_id
        WHERE sator.area = v_area
          AND sator.role = 'sator'
          AND u.role = 'promotor'
          AND EXISTS (
            SELECT 1 FROM sales_sell_out s
            WHERE s.promotor_id = u.id
              AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
              AND COALESCE(s.is_chip_sale, false) = false
          )
      )
      SELECT
        ss.sator_id,
        ss.sator_name,
        COUNT(DISTINCT ss.promotor_id) as promotor_count,
        (
          SELECT COUNT(*)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        ) as total_sales,
        (
          SELECT COALESCE(SUM(s.price_at_transaction), 0)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        ) as total_revenue,
        (
          SELECT COALESCE(SUM(s.estimated_bonus), 0)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
            AND COALESCE(s.is_chip_sale, false) = false
        ) as total_bonus,
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
                  'bonus', s.estimated_bonus,
                  'is_chip_sale', s.is_chip_sale
                ) ORDER BY s.created_at DESC
              )
              FROM sales_sell_out s
              JOIN product_variants pv ON pv.id = s.variant_id
              JOIN products p ON p.id = pv.product_id
              WHERE s.promotor_id = ss.promotor_id
                AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
                AND COALESCE(s.is_chip_sale, false) = false
            )
          ) ORDER BY ss.promotor_name
        ) as sales_list
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
        sator.id as sator_id,
        sator.full_name as sator_name,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', u.id,
            'promotor_name', u.full_name,
            'promotor_type', COALESCE(u.promotor_type, 'official')
          ) ORDER BY u.full_name
        ) as no_sales_list
      FROM users sator
      INNER JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = sator.id AND hsp.active = true
      INNER JOIN users u ON u.id = hsp.promotor_id
      WHERE sator.area = v_area
        AND sator.role = 'sator'
        AND u.role = 'promotor'
        AND NOT EXISTS (
          SELECT 1 FROM sales_sell_out s
          WHERE s.promotor_id = u.id
            AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
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
        AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
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
) AS $$
DECLARE
    v_user_role TEXT;
    v_user_area TEXT;
BEGIN
    SELECT u.role, u.area INTO v_user_role, v_user_area
    FROM users u
    WHERE u.id = p_user_id;

    RETURN QUERY
    SELECT
        so.id as feed_id,
        'sale'::TEXT as feed_type,
        so.id as sale_id,
        u.id as promotor_id,
        u.full_name as promotor_name,
        st.store_name,
        (p.series || ' ' || p.model_name) as product_name,
        (pv.ram_rom || ' ' || pv.color) as variant_name,
        so.price_at_transaction as price,
        so.estimated_bonus as bonus,
        so.payment_method,
        so.leasing_provider,
        so.customer_type::TEXT,
        so.notes,
        so.image_proof_url as image_url,
        COALESCE(
            (
                SELECT jsonb_object_agg(fr.reaction_type, fr.count)
                FROM (
                    SELECT fr.reaction_type, COUNT(*)::INTEGER as count
                    FROM feed_reactions fr
                    WHERE fr.sale_id = so.id
                    GROUP BY fr.reaction_type
                ) fr
            ),
            '{}'::jsonb
        ) as reaction_counts,
        COALESCE(
            (
                SELECT array_agg(fr.reaction_type)
                FROM feed_reactions fr
                WHERE fr.sale_id = so.id AND fr.user_id = p_user_id
            ),
            ARRAY[]::TEXT[]
        ) as user_reactions,
        COALESCE(
            (
                SELECT COUNT(*)::INTEGER
                FROM feed_comments fc
                WHERE fc.sale_id = so.id AND fc.deleted_at IS NULL
            ),
            0
        ) as comment_count,
        so.created_at
    FROM sales_sell_out so
    JOIN users u ON u.id = so.promotor_id
    JOIN stores st ON st.id = so.store_id
    JOIN product_variants pv ON pv.id = so.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE so.transaction_date = p_date
      AND so.deleted_at IS NULL
      AND COALESCE(so.is_chip_sale, false) = false
      AND (v_user_role != 'promotor' OR st.area = v_user_area)
    ORDER BY so.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_team_leaderboard(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period TEXT;
  v_start_date DATE;
  v_end_date DATE;
BEGIN
  v_period := COALESCE(p_period, TO_CHAR(CURRENT_DATE, 'YYYY-MM'));
  v_start_date := (v_period || '-01')::DATE;
  v_end_date := (v_start_date + INTERVAL '1 month')::DATE;

  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'rank', row_number,
        'promotor_id', promotor_id,
        'promotor_name', full_name,
        'store_name', store_name,
        'total_units', total_units,
        'total_revenue', total_revenue,
        'total_bonus', total_bonus
      ) ORDER BY total_revenue DESC
    ), '[]'::json)
    FROM (
      SELECT
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(s.price_at_transaction), 0) DESC) as row_number,
        u.id as promotor_id,
        u.full_name,
        st.store_name,
        COUNT(s.id) as total_units,
        COALESCE(SUM(s.price_at_transaction), 0) as total_revenue,
        COALESCE(SUM(s.estimated_bonus), 0) as total_bonus
      FROM users u
      INNER JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = u.id
        AND hsp.sator_id = p_sator_id AND hsp.active = true
      LEFT JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
      LEFT JOIN stores st ON st.id = aps.store_id
      LEFT JOIN sales_sell_out s ON s.promotor_id = u.id
        AND s.transaction_date >= v_start_date
        AND s.transaction_date < v_end_date
        AND s.deleted_at IS NULL
        AND COALESCE(s.is_chip_sale, false) = false
      WHERE u.role = 'promotor'
      GROUP BY u.id, u.full_name, st.store_name
    ) sub
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sator_leaderboard(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period TEXT;
  v_start_date DATE;
  v_end_date DATE;
BEGIN
  v_period := COALESCE(p_period, TO_CHAR(CURRENT_DATE, 'YYYY-MM'));
  v_start_date := (v_period || '-01')::DATE;
  v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::DATE;

  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.total_revenue DESC), '[]'::json)
    FROM (
      SELECT
        u.id AS promotor_id,
        u.full_name AS promotor_name,
        s.name AS store_name,
        COUNT(so.id) AS total_units,
        COALESCE(SUM(so.price_at_transaction), 0) AS total_revenue,
        COALESCE(SUM(so.estimated_bonus), 0) AS total_bonus,
        COALESCE(
          CASE
            WHEN mt.target_revenue > 0 THEN
              ROUND(COALESCE(SUM(so.price_at_transaction), 0) / mt.target_revenue * 100, 1)
            ELSE 0
          END,
          0
        ) AS achievement_percent
      FROM hierarchy_sator_promotor hsp
      INNER JOIN users u ON hsp.promotor_id = u.id
      LEFT JOIN assignments_promotor_store aps ON u.id = aps.promotor_id AND aps.active = true
      LEFT JOIN stores s ON aps.store_id = s.id
      LEFT JOIN sales_sell_out so ON u.id = so.promotor_id
        AND so.transaction_date BETWEEN v_start_date AND v_end_date
        AND COALESCE(so.is_chip_sale, false) = false
      LEFT JOIN monthly_targets mt ON u.id = mt.user_id
        AND mt.period = v_period
        AND mt.target_type = 'revenue'
      WHERE hsp.sator_id = p_sator_id
        AND hsp.active = true
      GROUP BY u.id, u.full_name, s.name, mt.target_revenue
    ) t
  );
END;
$$;

-- 4. Normalize existing chip sales so historical ranking/bonus stops counting them.
UPDATE public.sales_sell_out
SET estimated_bonus = 0,
    chip_label_visible = true
WHERE COALESCE(is_chip_sale, false) = true
  AND COALESCE(estimated_bonus, 0) <> 0;

-- 5. Recalculate dashboard bonus totals excluding chip sales.
UPDATE public.dashboard_performance_metrics dpm
SET estimated_bonus_total = (
  SELECT COALESCE(SUM(so.estimated_bonus), 0)
  FROM public.sales_sell_out so
  JOIN public.target_periods tp ON tp.id = dpm.period_id
  WHERE so.promotor_id = dpm.user_id
    AND so.transaction_date >= tp.start_date
    AND so.transaction_date <= tp.end_date
    AND COALESCE(so.is_chip_sale, false) = false
),
total_units_sold = (
  SELECT COALESCE(COUNT(*), 0)
  FROM public.sales_sell_out so
  JOIN public.target_periods tp ON tp.id = dpm.period_id
  WHERE so.promotor_id = dpm.user_id
    AND so.transaction_date >= tp.start_date
    AND so.transaction_date <= tp.end_date
    AND COALESCE(so.is_chip_sale, false) = false
),
total_units_focus = (
  SELECT COALESCE(COUNT(*), 0)
  FROM public.sales_sell_out so
  JOIN public.target_periods tp ON tp.id = dpm.period_id
  JOIN public.product_variants pv ON pv.id = so.variant_id
  JOIN public.products p ON p.id = pv.product_id
  WHERE so.promotor_id = dpm.user_id
    AND so.transaction_date >= tp.start_date
    AND so.transaction_date <= tp.end_date
    AND COALESCE(so.is_chip_sale, false) = false
    AND p.is_focus = true
),
last_updated = NOW();
