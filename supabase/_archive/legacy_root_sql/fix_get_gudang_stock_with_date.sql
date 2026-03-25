-- =====================================================
-- FIX GET GUDANG STOCK - ADD DATE PARAMETER
-- Date: 04 February 2026
-- Description: Update get_gudang_stock to accept date parameter
-- =====================================================

-- Drop old function
DROP FUNCTION IF EXISTS get_gudang_stock(UUID);

-- Create new function with date parameter (defaults to today)
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

GRANT EXECUTE ON FUNCTION get_gudang_stock(UUID, DATE) TO authenticated;
