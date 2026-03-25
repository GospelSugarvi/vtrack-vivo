-- =====================================================
-- PERBAIKAN URGENT - JALANKAN FILE INI DULU!
-- Date: 20 February 2026
-- =====================================================

-- STEP 1: Perbaiki fungsi get_stok_gudang_status_for_date
DROP FUNCTION IF EXISTS get_stok_gudang_status_for_date(DATE);

CREATE OR REPLACE FUNCTION get_stok_gudang_status_for_date(p_tanggal DATE)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_build_object(
    'has_data', EXISTS(
      SELECT 1 FROM warehouse_stock_daily 
      WHERE report_date = p_tanggal
    ),
    'created_by', (
      SELECT u.full_name 
      FROM warehouse_stock_daily wsd
      JOIN users u ON wsd.area = u.area
      WHERE wsd.report_date = p_tanggal
      LIMIT 1
    ),
    'created_at', (
      SELECT wsd.created_at 
      FROM warehouse_stock_daily wsd
      WHERE wsd.report_date = p_tanggal
      ORDER BY wsd.created_at ASC
      LIMIT 1
    ),
    'total_items', (
      SELECT COUNT(DISTINCT variant_id)
      FROM warehouse_stock_daily 
      WHERE report_date = p_tanggal
    )
  );
$$;

-- STEP 2: Perbaiki fungsi get_gudang_stock (TANPA FILTER AREA)
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
  -- Get user area
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
    -- JOIN TANPA FILTER AREA - hanya match variant_id dan tanggal
    LEFT JOIN warehouse_stock_daily wsd ON pv.id = wsd.variant_id 
      AND wsd.report_date = p_tanggal
    WHERE p.status = 'active' AND pv.active = true
  );
END;
$$;

-- STEP 3: Grant permissions
GRANT EXECUTE ON FUNCTION get_stok_gudang_status_for_date(DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_gudang_stock(UUID, DATE) TO authenticated;

-- STEP 4: Verify
SELECT '✅ PERBAIKAN BERHASIL!' as status;

-- Test untuk tanggal 20 Feb 2026
SELECT 
  'Data untuk 20 Feb 2026:' as info,
  COUNT(*) as total_products,
  SUM(CASE WHEN quantity > 0 THEN 1 ELSE 0 END) as products_with_stock,
  SUM(quantity) as total_quantity
FROM warehouse_stock_daily wsd
JOIN product_variants pv ON wsd.variant_id = pv.id
WHERE wsd.report_date = '2026-02-20';

-- Show sample data
SELECT 
  p.model_name,
  pv.ram_rom,
  pv.color,
  wsd.quantity,
  wsd.warehouse_code
FROM warehouse_stock_daily wsd
JOIN product_variants pv ON wsd.variant_id = pv.id
JOIN products p ON pv.product_id = p.id
WHERE wsd.report_date = '2026-02-20'
ORDER BY wsd.quantity DESC
LIMIT 10;
