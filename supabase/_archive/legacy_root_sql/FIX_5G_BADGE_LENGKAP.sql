-- =====================================================
-- FIX 5G BADGE LENGKAP - JALANKAN FILE INI!
-- Date: 20 February 2026
-- Purpose: Fix 5G badge not showing in export image
-- =====================================================

-- STEP 1: Update fungsi get_gudang_stock untuk include network_type
DROP FUNCTION IF EXISTS get_gudang_stock(uuid);
DROP FUNCTION IF EXISTS get_gudang_stock(uuid, date);

CREATE OR REPLACE FUNCTION get_gudang_stock(
  p_sator_id UUID,
  p_tanggal DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_area TEXT;
BEGIN
  SELECT area INTO v_user_area FROM users WHERE id = p_sator_id;
  
  IF v_user_area IS NULL OR TRIM(v_user_area) = '' THEN
    v_user_area := 'Gudang';
  END IF;
  
  v_user_area := TRIM(v_user_area);

  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'product_id', p.id,
        'product_name', p.model_name,
        'series', p.series,
        'network_type', p.network_type,
        'variant', pv.ram_rom,
        'color', pv.color,
        'price', pv.srp,
        'qty', COALESCE(wsd.quantity, 0),
        'otw', 0,
        'last_updated', wsd.updated_at,
        'category', CASE 
          WHEN COALESCE(wsd.quantity, 0) >= 10 THEN 'plenty'
          WHEN COALESCE(wsd.quantity, 0) >= 5 THEN 'enough'
          WHEN COALESCE(wsd.quantity, 0) > 0 THEN 'critical'
          ELSE 'empty'
        END
      ) ORDER BY 
        COALESCE(wsd.quantity, 0) DESC,
        pv.srp ASC
    ), '[]'::json)
    FROM products p
    INNER JOIN product_variants pv ON p.id = pv.product_id
    LEFT JOIN warehouse_stock_daily wsd ON pv.id = wsd.variant_id 
      AND wsd.report_date = p_tanggal
    WHERE p.status = 'active' AND pv.active = true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_gudang_stock(UUID, DATE) TO authenticated;

-- STEP 2: Update produk yang harusnya 5G tapi belum di-set

-- Products with "5G" in name
UPDATE products 
SET network_type = '5G'
WHERE status = 'active'
  AND (network_type IS NULL OR network_type = '4G')
  AND model_name ILIKE '%5G%';

-- X-series flagships
UPDATE products 
SET network_type = '5G'
WHERE status = 'active'
  AND (network_type IS NULL OR network_type = '4G')
  AND (
    model_name ILIKE '%X100%' OR model_name ILIKE '%X90%' OR model_name ILIKE '%X80%'
    OR model_name ILIKE '%X70%' OR model_name ILIKE '%X60%'
  );

-- V-series 5G models
UPDATE products 
SET network_type = '5G'
WHERE status = 'active'
  AND (network_type IS NULL OR network_type = '4G')
  AND (
    model_name ILIKE '%V40%' OR model_name ILIKE '%V30%' OR model_name ILIKE '%V29%'
    OR model_name ILIKE '%V27%' OR model_name ILIKE '%V25%' OR model_name ILIKE '%V23%'
  );

-- Y-series 5G models
UPDATE products 
SET network_type = '5G'
WHERE status = 'active'
  AND (network_type IS NULL OR network_type = '4G')
  AND (
    model_name ILIKE '%Y100%' OR model_name ILIKE '%Y36 5G%' 
    OR model_name ILIKE '%Y27 5G%' OR model_name ILIKE '%Y200%'
  );

-- iQOO series
UPDATE products 
SET network_type = '5G'
WHERE status = 'active'
  AND (network_type IS NULL OR network_type = '4G')
  AND (model_name ILIKE '%IQOO%' OR model_name ILIKE '%iQOO%');

-- STEP 3: Show results
SELECT 
  '✅ PERBAIKAN 5G BADGE SELESAI!' as status,
  (SELECT COUNT(*) FROM products WHERE network_type = '5G' AND status = 'active') as total_5g_products,
  (SELECT COUNT(*) FROM products WHERE network_type = '4G' AND status = 'active') as total_4g_products;

-- Show 5G products
SELECT 
  model_name,
  series,
  network_type,
  COUNT(pv.id) as variants
FROM products p
LEFT JOIN product_variants pv ON p.id = pv.product_id
WHERE p.status = 'active' AND p.network_type = '5G'
GROUP BY p.id, p.model_name, p.series, p.network_type
ORDER BY p.series, p.model_name;

-- Test with sample data from Feb 20
SELECT 
  p.model_name,
  p.series,
  p.network_type,
  pv.ram_rom,
  pv.color,
  wsd.quantity
FROM products p
INNER JOIN product_variants pv ON p.id = pv.product_id
LEFT JOIN warehouse_stock_daily wsd ON pv.id = wsd.variant_id 
  AND wsd.report_date = '2026-02-20'
WHERE p.status = 'active' 
  AND pv.active = true
  AND wsd.quantity IS NOT NULL
  AND p.network_type = '5G'
ORDER BY wsd.quantity DESC
LIMIT 10;
