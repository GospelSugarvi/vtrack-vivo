-- ==========================================================
-- FIX get_store_stock_status - SHOW ALL STORES
-- ==========================================================

DROP FUNCTION IF EXISTS get_store_stock_status(UUID);

CREATE FUNCTION get_store_stock_status(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'store_id', id,
      'store_name', store_name,
      'area', COALESCE(area, ''),
      'grade', COALESCE(grade, 'B'),
      'empty_count', 0,
      'low_count', 0,
      'ok_count', 0
    )
  )
  INTO v_result
  FROM stores
  WHERE deleted_at IS NULL
  ORDER BY store_name;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;
