-- Fix: get_store_stock_status should return JSON properly.
-- Date: 2026-03-12

DROP FUNCTION IF EXISTS public.get_store_stock_status(UUID);
CREATE OR REPLACE FUNCTION public.get_store_stock_status(p_sator_id UUID)
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
  store_ids AS (
    SELECT DISTINCT store_id
    FROM assignments_promotor_store
    WHERE promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', st.id,
      'store_name', st.store_name,
      'group_id', st.group_id,
      'group_name', sg.group_name,
      'empty_count', (
        SELECT COUNT(*) FROM store_inventory si
        WHERE si.store_id = st.id AND si.quantity = 0
      ),
      'low_count', (
        SELECT COUNT(*) FROM store_inventory si
        WHERE si.store_id = st.id AND si.quantity > 0 AND si.quantity < 3
      )
    )
  ), '[]'::json)
  INTO v_result
  FROM stores st
  LEFT JOIN store_groups sg ON sg.id = st.group_id
  WHERE st.id IN (SELECT store_id FROM store_ids);

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_store_stock_status(UUID) TO authenticated;

