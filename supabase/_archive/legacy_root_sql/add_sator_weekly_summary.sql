-- Add function to get weekly summary for sator

CREATE OR REPLACE FUNCTION get_sator_weekly_summary(
  p_sator_id uuid,
  p_start_date date DEFAULT CURRENT_DATE - INTERVAL '7 days',
  p_end_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Get sales summary for stores assigned to sator for date range
  SELECT jsonb_build_object(
    'total_sales', COALESCE(COUNT(*), 0),
    'total_revenue', COALESCE(SUM(so.price_at_transaction), 0),
    'active_sellers', COALESCE(COUNT(DISTINCT so.promotor_id), 0),
    'active_stores', COALESCE(COUNT(DISTINCT so.store_id), 0),
    'start_date', p_start_date,
    'end_date', p_end_date
  )
  INTO v_result
  FROM sales_sell_out so
  INNER JOIN assignments_promotor_store aps 
    ON aps.promotor_id = so.promotor_id AND aps.active = true
  INNER JOIN assignments_sator_store ass 
    ON ass.store_id = aps.store_id 
    AND ass.sator_id = p_sator_id 
    AND ass.active = true
  WHERE so.transaction_date BETWEEN p_start_date AND p_end_date
    AND so.deleted_at IS NULL;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_sator_weekly_summary(uuid, date, date) TO authenticated;

-- Test for ANTONIO
SELECT 'Weekly summary for ANTONIO (last 7 days):' as test;
SELECT get_sator_weekly_summary(
  (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
  (CURRENT_DATE - INTERVAL '7 days')::date,
  CURRENT_DATE
);

SELECT 'This month summary for ANTONIO:' as test;
SELECT get_sator_weekly_summary(
  (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
  DATE_TRUNC('month', CURRENT_DATE)::date,
  CURRENT_DATE
);
