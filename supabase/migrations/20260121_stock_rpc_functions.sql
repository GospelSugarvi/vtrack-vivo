-- RPC Function for Stock Summary by Store

CREATE OR REPLACE FUNCTION get_stock_summary_by_store()
RETURNS TABLE (
  store_id UUID,
  store_name TEXT,
  fresh_count BIGINT,
  chip_count BIGINT,
  display_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    st.id as store_id,
    st.store_name,
    COALESCE(COUNT(*) FILTER (WHERE s.tipe_stok = 'fresh'), 0)::BIGINT as fresh_count,
    COALESCE(COUNT(*) FILTER (WHERE s.tipe_stok = 'chip'), 0)::BIGINT as chip_count,
    COALESCE(COUNT(*) FILTER (WHERE s.tipe_stok = 'display'), 0)::BIGINT as display_count
  FROM stores st
  LEFT JOIN stok s ON st.id = s.store_id AND s.is_sold = false
  WHERE st.deleted_at IS NULL
  GROUP BY st.id, st.store_name
  ORDER BY st.store_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
