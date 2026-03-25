-- Update Sator Functions to Use Store Assignment
-- Run this file only (skip migration file if already exists)

-- Drop and recreate functions to fix return type issues

-- 1. Drop existing functions
DROP FUNCTION IF EXISTS get_store_stock_status(uuid);
DROP FUNCTION IF EXISTS get_sator_daily_summary(uuid, date);
DROP FUNCTION IF EXISTS get_sator_kpi_summary(uuid);
DROP FUNCTION IF EXISTS get_sator_alerts(uuid);

-- 2. Recreate get_store_stock_status
CREATE FUNCTION get_store_stock_status(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Get stores assigned to this sator with stock status
  SELECT jsonb_agg(
    jsonb_build_object(
      'store_id', s.id,
      'store_name', s.store_name,
      'area', s.area,
      'empty_count', COALESCE(stock_status.empty_count, 0),
      'low_count', COALESCE(stock_status.low_count, 0),
      'ok_count', COALESCE(stock_status.ok_count, 0)
    )
  )
  INTO v_result
  FROM stores s
  INNER JOIN assignments_sator_store ass 
    ON ass.store_id = s.id 
    AND ass.sator_id = p_sator_id 
    AND ass.active = true
  LEFT JOIN LATERAL (
    SELECT 
      COUNT(*) FILTER (WHERE si.quantity = 0) as empty_count,
      COUNT(*) FILTER (WHERE si.quantity > 0 AND si.quantity < 5) as low_count,
      COUNT(*) FILTER (WHERE si.quantity >= 5) as ok_count
    FROM store_inventory si
    WHERE si.store_id = s.id
  ) stock_status ON true
  WHERE s.deleted_at IS NULL;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Recreate get_sator_daily_summary
CREATE FUNCTION get_sator_daily_summary(p_sator_id uuid, p_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Get sales summary for stores assigned to sator
  SELECT jsonb_build_object(
    'total_sales', COALESCE(COUNT(*), 0),
    'total_revenue', COALESCE(SUM(so.price_at_transaction), 0),
    'active_sellers', COALESCE(COUNT(DISTINCT so.promotor_id), 0)
  )
  INTO v_result
  FROM sales_sell_out so
  INNER JOIN assignments_promotor_store aps 
    ON aps.promotor_id = so.promotor_id AND aps.active = true
  INNER JOIN assignments_sator_store ass 
    ON ass.store_id = aps.store_id 
    AND ass.sator_id = p_sator_id 
    AND ass.active = true
  WHERE so.transaction_date = p_date
    AND so.deleted_at IS NULL;

  RETURN v_result;
END;
$$;

-- 4. Recreate get_sator_kpi_summary
CREATE FUNCTION get_sator_kpi_summary(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Placeholder - return default values
  SELECT jsonb_build_object(
    'total_score', 0,
    'sell_out_all_score', 0,
    'sell_out_fokus_score', 0,
    'sell_in_score', 0,
    'kpi_ma_score', 0
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

-- 5. Recreate get_sator_alerts
CREATE FUNCTION get_sator_alerts(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Placeholder - return empty array
  RETURN '[]'::jsonb;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_daily_summary(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_kpi_summary(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_alerts(uuid) TO authenticated;

-- Test the functions
SELECT 'Functions updated successfully!' as status;
SELECT 'Testing get_store_stock_status for ANTONIO...' as test;
SELECT get_store_stock_status(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo')
);
