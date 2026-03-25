-- =====================================================
-- STOK GUDANG DATE CHECK FUNCTION
-- Date: 04 February 2026
-- Description: Function to check stock status for specific date
-- =====================================================

-- Function to check if stock exists for a specific date
DROP FUNCTION IF EXISTS get_stok_gudang_status_for_date(DATE);

CREATE OR REPLACE FUNCTION get_stok_gudang_status_for_date(p_tanggal DATE)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_build_object(
    'has_data', EXISTS(SELECT 1 FROM stok_gudang_harian WHERE tanggal = p_tanggal),
    'created_by', (
      SELECT u.full_name 
      FROM stok_gudang_harian sgh
      JOIN users u ON sgh.created_by = u.id
      WHERE sgh.tanggal = p_tanggal
      LIMIT 1
    ),
    'created_at', (
      SELECT sgh.created_at 
      FROM stok_gudang_harian sgh
      WHERE sgh.tanggal = p_tanggal
      ORDER BY sgh.created_at ASC
      LIMIT 1
    ),
    'total_items', (
      SELECT COUNT(DISTINCT (product_id, variant_id))
      FROM stok_gudang_harian 
      WHERE tanggal = p_tanggal
    )
  );
$$;

GRANT EXECUTE ON FUNCTION get_stok_gudang_status_for_date(DATE) TO authenticated;
