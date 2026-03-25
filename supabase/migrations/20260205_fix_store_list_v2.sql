-- ==========================================================
-- DROP SEMUA VERSI get_store_stock_status LALU BUAT BARU
-- ==========================================================

-- Drop semua versi
DROP FUNCTION IF EXISTS get_store_stock_status(uuid);
DROP FUNCTION IF EXISTS get_store_stock_status(UUID);
DROP FUNCTION IF EXISTS get_store_stock_status(text);
DROP FUNCTION IF EXISTS get_store_stock_status(TEXT);

-- Buat baru - sangat simple
CREATE FUNCTION get_store_stock_status(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
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
    FROM stores
    WHERE deleted_at IS NULL
    ORDER BY store_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;
