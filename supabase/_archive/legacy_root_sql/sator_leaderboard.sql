-- SATOR Leaderboard Function
-- Returns promotor rankings within SATOR's team for a given period

CREATE OR REPLACE FUNCTION get_sator_leaderboard(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL -- format: 'YYYY-MM'
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
  -- Default to current month if no period specified
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
