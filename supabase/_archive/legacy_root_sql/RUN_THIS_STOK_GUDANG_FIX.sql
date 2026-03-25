-- =====================================================
-- STOK GUDANG COMPLETE FIX
-- Date: 04 February 2026
-- Description: Run this file to fix all stok gudang functions
-- =====================================================

-- 1. Function to check stock status for specific date
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

-- 2. Update get_gudang_stock to accept date parameter
DROP FUNCTION IF EXISTS get_gudang_stock(UUID);
DROP FUNCTION IF EXISTS get_gudang_stock(UUID, DATE);

CREATE OR REPLACE FUNCTION get_gudang_stock(
    p_sator_id UUID,
    p_tanggal DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    json_agg(
      json_build_object(
        'product_id', p.id,
        'product_name', p.model_name,
        'variant', pv.ram_rom,
        'color', pv.color,
        'price', pv.srp,
        'qty', COALESCE(sgh.stok_gudang, 0),
        'otw', COALESCE(sgh.stok_otw, 0),
        'category', CASE 
          WHEN COALESCE(sgh.stok_gudang, 0) = 0 THEN 'empty'
          WHEN COALESCE(sgh.stok_gudang, 0) < 5 THEN 'critical'
          WHEN COALESCE(sgh.stok_gudang, 0) < 10 THEN 'enough'
          ELSE 'plenty'
        END
      ) ORDER BY 
        CASE WHEN COALESCE(sgh.stok_gudang, 0) = 0 THEN 1 ELSE 0 END,
        pv.srp ASC
    ),
    '[]'::json
  )
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  LEFT JOIN stok_gudang_harian sgh ON p.id = sgh.product_id 
       AND pv.id = sgh.variant_id 
       AND sgh.tanggal = p_tanggal
  WHERE pv.active = true;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_stok_gudang_status_for_date(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_gudang_stock(UUID, DATE) TO authenticated;

-- Test query to verify
SELECT 'Functions created successfully!' as status;

-- Show recent stock data
SELECT 
    tanggal,
    COUNT(*) as total_items,
    SUM(stok_gudang) as total_stok_gudang,
    SUM(stok_otw) as total_stok_otw
FROM stok_gudang_harian
GROUP BY tanggal
ORDER BY tanggal DESC
LIMIT 5;
