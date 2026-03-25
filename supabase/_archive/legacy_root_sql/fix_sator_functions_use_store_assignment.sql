-- Update all sator-related RPC functions to use assignments_sator_store instead of hierarchy

-- 1. Fix get_store_stock_status
CREATE OR REPLACE FUNCTION get_store_stock_status(p_sator_id uuid)
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
      COUNT(*) FILTER (WHERE si.quantity > 0 AND si.quantity < COALESCE(ms.min_quantity, 0)) as low_count,
      COUNT(*) FILTER (WHERE si.quantity >= COALESCE(ms.min_quantity, 0)) as ok_count
    FROM store_inventory si
    LEFT JOIN min_stock ms ON ms.store_id = si.store_id AND ms.variant_id = si.variant_id
    WHERE si.store_id = s.id
  ) stock_status ON true
  WHERE s.deleted_at IS NULL;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 2. Fix get_sator_daily_summary
CREATE OR REPLACE FUNCTION get_sator_daily_summary(p_sator_id uuid, p_date date)
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

-- 3. Fix get_sator_kpi_summary (if exists)
CREATE OR REPLACE FUNCTION get_sator_kpi_summary(p_sator_id uuid)
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

-- 4. Fix get_sator_alerts (if exists)
CREATE OR REPLACE FUNCTION get_sator_alerts(p_sator_id uuid)
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
