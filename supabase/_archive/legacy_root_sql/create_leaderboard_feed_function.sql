-- Function to generate leaderboard feed data
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
    SELECT jsonb_agg(
      jsonb_build_object(
        'name', u.full_name,
        'total_bonus', COALESCE(SUM(s.bonus), 0)
      ) ORDER BY COALESCE(SUM(s.bonus), 0) DESC
    )
    INTO v_top_bonus
    FROM users u
    LEFT JOIN sales_sell_out s ON s.promotor_id = u.id 
      AND DATE(s.created_at AT TIME ZONE 'Asia/Makassar') = p_date
    WHERE u.area = v_area
      AND u.role = 'promotor'
    GROUP BY u.id, u.full_name
    HAVING COALESCE(SUM(s.bonus), 0) > 0
    ORDER BY COALESCE(SUM(s.bonus), 0) DESC
    LIMIT 3;

    IF v_top_bonus IS NOT NULL AND jsonb_array_length(v_top_bonus) > 0 THEN
      v_result := v_result || jsonb_build_object(
        'feed_type', 'top_bonus',
        'area_name', v_area,
        'top_bonus_list', v_top_bonus
      );
    END IF;

    -- Sales list grouped by sator
    FOR v_sales_by_sator IN
      SELECT 
        sator.id as sator_id,
        sator.full_name as sator_name,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', u.id,
            'promotor_name', u.full_name,
            'promotor_type', u.promotor_type
          ) ORDER BY u.full_name
        ) as sales_list
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
      GROUP BY sator.id, sator.full_name
      ORDER BY sator.full_name
    LOOP
      v_result := v_result || jsonb_build_object(
        'feed_type', 'sales_list',
        'area_name', v_area,
        'sator_id', v_sales_by_sator.sator_id,
        'sator_name', v_sales_by_sator.sator_name,
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
            'promotor_type', u.promotor_type
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

  END LOOP;

  RETURN v_result;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_leaderboard_feed(UUID, DATE) TO authenticated;
