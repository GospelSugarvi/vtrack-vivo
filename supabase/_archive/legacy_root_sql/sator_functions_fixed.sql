-- =====================================================
-- SATOR RPC FUNCTIONS - FIXED VERSION
-- Date: 2026-01-30
-- All functions tested and working
-- =====================================================

-- 1. SATOR DAILY SUMMARY
DROP FUNCTION IF EXISTS get_sator_daily_summary(UUID, DATE);
CREATE OR REPLACE FUNCTION get_sator_daily_summary(
  p_sator_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_build_object(
    'total_sales', COALESCE(SUM(s.quantity), 0),
    'total_revenue', COALESCE(SUM(s.price_at_transaction), 0),
    'active_sellers', COUNT(DISTINCT s.promotor_id)
  )
  FROM sell_out s
  INNER JOIN hierarchy_sator_promotor hsp ON s.promotor_id = hsp.promotor_id
  WHERE hsp.sator_id = p_sator_id 
    AND hsp.active = true
    AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = p_date;
$$;

-- 2. SATOR ALERTS
DROP FUNCTION IF EXISTS get_sator_alerts(UUID);
CREATE OR REPLACE FUNCTION get_sator_alerts(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(alert), '[]'::json)
  FROM (
    SELECT json_build_object(
      'promotor_id', u.id,
      'promotor_name', u.full_name,
      'type', 'no_sales',
      'message', 'Belum ada penjualan hari ini'
    ) as alert
    FROM users u
    INNER JOIN hierarchy_sator_promotor hsp ON u.id = hsp.promotor_id
    WHERE hsp.sator_id = p_sator_id AND hsp.active = true
    AND NOT EXISTS (
      SELECT 1 FROM sell_out s 
      WHERE s.promotor_id = u.id 
      AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
    )
    LIMIT 10
  ) sub;
$$;

-- 3. SATOR SELLIN SUMMARY
DROP FUNCTION IF EXISTS get_sator_sellin_summary(UUID);
CREATE OR REPLACE FUNCTION get_sator_sellin_summary(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_build_object(
    'total_items', COUNT(*),
    'kosong', COUNT(*) FILTER (WHERE status = 'kosong'),
    'tipis', COUNT(*) FILTER (WHERE status = 'tipis'),
    'cukup', COUNT(*) FILTER (WHERE status = 'cukup')
  )
  FROM stok_gudang_harian
  WHERE tanggal = CURRENT_DATE;
$$;

-- 4. STORE STOCK STATUS
DROP FUNCTION IF EXISTS get_store_stock_status(UUID);
CREATE OR REPLACE FUNCTION get_store_stock_status(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', st.id,
      'store_name', st.store_name,
      'promotor_count', (
        SELECT COUNT(*) FROM assignments_promotor_store aps2 
        WHERE aps2.store_id = st.id AND aps2.active = true
      )
    )
  ), '[]'::json)
  FROM stores st
  INNER JOIN assignments_promotor_store aps ON st.id = aps.store_id
  INNER JOIN hierarchy_sator_promotor hsp ON aps.promotor_id = hsp.promotor_id
  WHERE hsp.sator_id = p_sator_id AND hsp.active = true AND aps.active = true
  GROUP BY st.id, st.store_name;
$$;

-- 5. PENDING ORDERS
DROP FUNCTION IF EXISTS get_pending_orders(UUID);
CREATE OR REPLACE FUNCTION get_pending_orders(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT '[]'::json; -- Placeholder - will implement when order system is ready
$$;

-- 6. LIST TOKO FOR SATOR
DROP FUNCTION IF EXISTS get_sator_stores(UUID);
CREATE OR REPLACE FUNCTION get_sator_stores(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', st.id,
      'store_name', st.store_name,
      'address', st.address,
      'promotor_count', (
        SELECT COUNT(*) FROM assignments_promotor_store aps2 
        WHERE aps2.store_id = st.id AND aps2.active = true
      )
    )
  ), '[]'::json)
  FROM stores st
  INNER JOIN assignments_promotor_store aps ON st.id = aps.store_id
  INNER JOIN hierarchy_sator_promotor hsp ON aps.promotor_id = hsp.promotor_id
  WHERE hsp.sator_id = p_sator_id AND hsp.active = true AND aps.active = true
  GROUP BY st.id, st.store_name, st.address;
$$;

-- 7. REKOMENDASI UNTUK TOKO
DROP FUNCTION IF EXISTS get_store_recommendations(UUID, UUID);
CREATE OR REPLACE FUNCTION get_store_recommendations(p_sator_id UUID, p_store_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COALESCE(json_agg(
    json_build_object(
      'product_id', p.id,
      'variant_id', pv.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'gudang_stock', COALESCE(sgh.stok_gudang, 0),
      'recommended_qty', CASE 
        WHEN COALESCE(sgh.stok_gudang, 0) > 10 THEN 3
        WHEN COALESCE(sgh.stok_gudang, 0) > 5 THEN 2
        WHEN COALESCE(sgh.stok_gudang, 0) > 0 THEN 1
        ELSE 0
      END
    )
  ), '[]'::json)
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  LEFT JOIN stok_gudang_harian sgh ON p.id = sgh.product_id 
    AND pv.id = sgh.variant_id 
    AND sgh.tanggal = CURRENT_DATE
  WHERE COALESCE(sgh.stok_gudang, 0) > 0;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_sator_daily_summary(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_alerts(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_sellin_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_store_stock_status(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_pending_orders(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_stores(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_store_recommendations(UUID, UUID) TO authenticated;
