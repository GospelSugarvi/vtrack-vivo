-- Function to generate leaderboard feed data
-- VERIFIED: All columns checked against schema
CREATE OR REPLACE FUNCTION get_leaderboard_feed(
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
  -- Get user role and area
  SELECT role, area INTO v_user_role, v_user_area
  FROM users
  WHERE id = p_user_id;

  -- Loop through areas (based on user access)
  FOR v_area IN
    SELECT DISTINCT u.area
    FROM users u
    WHERE u.role IN ('promotor', 'sator', 'spv')
      AND (v_user_role = 'admin' OR u.area = v_user_area)
      AND u.area IS NOT NULL
    ORDER BY u.area
  LOOP
    -- Area header with SPV name
    DECLARE
      v_spv_name TEXT;
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

    -- Top 3 bonus in this area
    WITH top_promotors AS (
      SELECT 
        u.full_name,
        COALESCE(SUM(s.estimated_bonus), 0) as total_bonus
      FROM users u
      LEFT JOIN sales_sell_out s ON s.promotor_id = u.id 
        AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
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

    -- Sales list grouped by sator
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
        ) as total_sales,
        (
          SELECT COALESCE(SUM(s.price_at_transaction), 0)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
        ) as total_revenue,
        (
          SELECT COALESCE(SUM(s.estimated_bonus), 0)
          FROM sales_sell_out s
          JOIN sator_sales ss2 ON ss2.promotor_id = s.promotor_id
          WHERE ss2.sator_id = ss.sator_id
            AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
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
                  'bonus', s.estimated_bonus
                ) ORDER BY s.created_at DESC
              )
              FROM sales_sell_out s
              JOIN product_variants pv ON pv.id = s.variant_id
              JOIN products p ON p.id = pv.product_id
              WHERE s.promotor_id = ss.promotor_id
                AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
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

    -- No sales list grouped by sator
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

    -- Area summary (total penjualan area)
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
        AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date;
      
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

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_leaderboard_feed(UUID, DATE) TO authenticated;
