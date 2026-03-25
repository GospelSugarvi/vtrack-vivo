-- ==========================================================
-- DEBUG: Buat function paling simple tanpa parameter
-- ==========================================================

-- Drop semua
DROP FUNCTION IF EXISTS get_store_stock_status(uuid);
DROP FUNCTION IF EXISTS get_store_stock_status(UUID);

-- Buat versi simple tanpa parameter
CREATE FUNCTION get_store_stock_status_simple()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'store_id', id,
        'store_name', store_name
      )
    )
    FROM stores
    WHERE deleted_at IS NULL
    LIMIT 10
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_store_stock_status_simple() TO authenticated;

-- Cek apakah tabel stores ada
SELECT COUNT(*) as total_stores FROM stores WHERE deleted_at IS NULL;
