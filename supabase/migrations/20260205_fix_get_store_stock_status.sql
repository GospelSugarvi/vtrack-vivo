-- ==========================================================
-- RECREATE: get_store_stock_status (tanpa ideal_qty)
-- ==========================================================

DROP FUNCTION IF EXISTS get_store_stock_status(uuid);

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
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) = 0) as empty_count,
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) > 0 AND COALESCE(si.quantity, 0) < 3) as low_count,
      COUNT(*) FILTER (WHERE COALESCE(si.quantity, 0) >= 3) as ok_count
    FROM store_inventory si
    WHERE si.store_id = s.id
  ) stock_status ON true
  WHERE s.deleted_at IS NULL;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;
