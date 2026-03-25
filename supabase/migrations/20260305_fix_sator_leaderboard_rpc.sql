-- Fix SATOR leaderboard RPC functions
-- Date: 2026-03-05
-- Problem: get_team_leaderboard and other sator RPCs reference non-existent
--   table 'sell_out' (correct: 'sales_sell_out'), column 's.quantity'
--   (doesn't exist — each row = 1 unit), and 's.sale_date'
--   (correct: 'transaction_date').
-- Impact: Sator leaderboard returns empty data while promotor works fine.

-- Drop existing functions first to avoid return-type conflicts
DROP FUNCTION IF EXISTS get_team_leaderboard(UUID, TEXT);
DROP FUNCTION IF EXISTS get_team_live_feed(UUID);
DROP FUNCTION IF EXISTS get_sator_daily_summary(UUID, DATE);

-- =====================================================
-- 1. FIX: get_team_leaderboard
-- Was: sell_out / s.quantity / s.sale_date
-- Now: sales_sell_out / COUNT(*) / transaction_date
-- =====================================================
CREATE OR REPLACE FUNCTION get_team_leaderboard(
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
      WHERE u.role = 'promotor'
      GROUP BY u.id, u.full_name, st.store_name
    ) sub
  );
END;
$$;

-- =====================================================
-- 2. FIX: get_team_live_feed
-- Was: activity_feed (may not exist or be empty)
-- Now: sales_sell_out with product info (matches promotor feed)
-- =====================================================
CREATE OR REPLACE FUNCTION get_team_live_feed(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'id', s.id,
        'type', 'sell_out',
        'promotor_id', u.id,
        'promotor_name', u.full_name,
        'store_name', st.store_name,
        'product_name', COALESCE(p.model_name, 'Produk'),
        'variant_name', COALESCE(pv.ram_rom, ''),
        'price', s.price_at_transaction,
        'bonus', s.estimated_bonus,
        'created_at', s.created_at
      ) ORDER BY s.created_at DESC
    ), '[]'::json)
    FROM sales_sell_out s
    INNER JOIN users u ON u.id = s.promotor_id
    LEFT JOIN stores st ON st.id = s.store_id
    LEFT JOIN product_variants pv ON pv.id = s.variant_id
    LEFT JOIN products p ON p.id = pv.product_id
    WHERE s.promotor_id IN (
      SELECT promotor_id FROM hierarchy_sator_promotor
      WHERE sator_id = p_sator_id AND active = true
    )
    AND s.created_at > NOW() - INTERVAL '24 hours'
    AND s.deleted_at IS NULL
    LIMIT 50
  );
END;
$$;

-- =====================================================
-- 3. FIX: get_sator_daily_summary
-- Was: sell_out / s.quantity / s.sale_date
-- Now: sales_sell_out / COUNT(*) / transaction_date
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_daily_summary(
  p_sator_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  daily_sales AS (
    SELECT
      COUNT(s.id) as total_sales,
      COALESCE(SUM(s.price_at_transaction), 0) as total_revenue,
      COUNT(DISTINCT s.promotor_id) as active_sellers
    FROM sales_sell_out s
    WHERE s.promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND s.transaction_date = p_date
    AND s.deleted_at IS NULL
  )
  SELECT json_build_object(
    'total_sales', total_sales,
    'total_revenue', total_revenue,
    'active_sellers', active_sellers
  ) INTO v_result
  FROM daily_sales;

  RETURN v_result;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_team_leaderboard(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_team_live_feed(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_daily_summary(UUID, DATE) TO authenticated;
