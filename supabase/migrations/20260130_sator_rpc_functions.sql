-- =====================================================
-- SATOR RPC FUNCTIONS
-- Created: 2026-01-30
-- Description: All RPC functions needed for SATOR role
-- =====================================================

-- =====================================================
-- 1. SATOR DAILY SUMMARY
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_daily_summary(
  p_sator_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- Get promotor IDs under this SATOR
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  daily_sales AS (
    SELECT 
      COALESCE(SUM(s.quantity), 0) as total_sales,
      COALESCE(SUM(s.price_at_transaction), 0) as total_revenue,
      COUNT(DISTINCT s.promotor_id) as active_sellers
    FROM sell_out s
    WHERE s.promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = p_date
  )
  SELECT json_build_object(
    'total_sales', total_sales,
    'total_revenue', total_revenue,
    'active_sellers', active_sellers
  ) INTO v_result
  FROM daily_sales;

  RETURN v_result;
END;
$$;

-- =====================================================
-- 2. SATOR KPI SUMMARY
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_kpi_summary(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_current_month TEXT;
BEGIN
  v_current_month := TO_CHAR(CURRENT_DATE, 'YYYY-MM');
  
  -- Calculate KPI scores (simplified version)
  WITH kpi_data AS (
    SELECT 
      COALESCE(sell_out_all_score, 0) as sell_out_all_score,
      COALESCE(sell_out_fokus_score, 0) as sell_out_fokus_score,
      COALESCE(sell_in_score, 0) as sell_in_score,
      COALESCE(kpi_ma_score, 0) as kpi_ma_score,
      COALESCE(total_score, 0) as total_score,
      COALESCE(bonus_amount, 0) as total_bonus
    FROM sator_monthly_kpi
    WHERE sator_id = p_sator_id
    AND period_month = v_current_month
  )
  SELECT json_build_object(
    'sell_out_all_score', COALESCE((SELECT sell_out_all_score FROM kpi_data), 0),
    'sell_out_fokus_score', COALESCE((SELECT sell_out_fokus_score FROM kpi_data), 0),
    'sell_in_score', COALESCE((SELECT sell_in_score FROM kpi_data), 0),
    'kpi_ma_score', COALESCE((SELECT kpi_ma_score FROM kpi_data), 0),
    'total_score', COALESCE((SELECT total_score FROM kpi_data), 0),
    'total_bonus', COALESCE((SELECT total_bonus FROM kpi_data), 0)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- =====================================================
-- 3. SATOR ALERTS
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_alerts(p_sator_id UUID)
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
  alerts AS (
    -- Promotors who haven't clocked in today
    SELECT 
      u.id as promotor_id,
      u.full_name as promotor_name,
      'no_clock' as type,
      'Belum clock-in hari ini' as message
    FROM users u
    INNER JOIN promotor_ids pi ON u.id = pi.promotor_id
    WHERE NOT EXISTS (
      SELECT 1 FROM attendance_logs al
      WHERE al.user_id = u.id
      AND DATE(al.clock_in AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
    )
    AND u.status = 'active'
    
    UNION ALL
    
    -- Promotors with no sales today (but clocked in)
    SELECT 
      u.id as promotor_id,
      u.full_name as promotor_name,
      'no_sales' as type,
      'Belum ada penjualan hari ini' as message
    FROM users u
    INNER JOIN promotor_ids pi ON u.id = pi.promotor_id
    WHERE EXISTS (
      SELECT 1 FROM attendance_logs al
      WHERE al.user_id = u.id
      AND DATE(al.clock_in AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
    )
    AND NOT EXISTS (
      SELECT 1 FROM sell_out s
      WHERE s.promotor_id = u.id
      AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE
    )
    AND u.status = 'active'
    
    LIMIT 10
  )
  SELECT COALESCE(json_agg(alerts), '[]'::json) INTO v_result FROM alerts;

  RETURN v_result;
END;
$$;

-- =====================================================
-- 4. SATOR SELL OUT SUMMARY
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_sellout_summary(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSON;
  v_period TEXT;
BEGIN
  v_period := COALESCE(p_period, TO_CHAR(CURRENT_DATE, 'YYYY-MM'));
  
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  summary AS (
    SELECT 
      COALESCE(SUM(s.quantity), 0) as total_units,
      COALESCE(SUM(s.price_at_transaction), 0) as total_revenue,
      COUNT(DISTINCT s.promotor_id) as active_promotors,
      COUNT(DISTINCT DATE(s.sale_date AT TIME ZONE 'Asia/Makassar')) as active_days
    FROM sell_out s
    WHERE s.promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND TO_CHAR(s.sale_date AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') = v_period
  )
  SELECT json_build_object(
    'total_units', total_units,
    'total_revenue', total_revenue,
    'active_promotors', active_promotors,
    'active_days', active_days
  ) INTO v_result
  FROM summary;

  RETURN v_result;
END;
$$;

-- =====================================================
-- 5. SATOR LIVE SALES
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_live_sales(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', s.id,
      'promotor_id', s.promotor_id,
      'promotor_name', u.full_name,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'price', s.price_at_transaction,
      'sale_time', s.sale_date
    ) ORDER BY s.sale_date DESC
  ), '[]'::json)
  FROM sell_out s
  INNER JOIN users u ON s.promotor_id = u.id
  INNER JOIN product_variants pv ON s.variant_id = pv.id
  INNER JOIN products p ON pv.product_id = p.id
  WHERE s.promotor_id IN (SELECT promotor_id FROM promotor_ids)
  AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE;
END;
$$;

-- =====================================================
-- 6. SATOR SALES PER TOKO
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_sales_per_toko(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period TEXT;
BEGIN
  v_period := COALESCE(p_period, TO_CHAR(CURRENT_DATE, 'YYYY-MM'));
  
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', st.id,
      'store_name', st.store_name,
      'total_units', COALESCE(SUM(s.quantity), 0),
      'total_revenue', COALESCE(SUM(s.price_at_transaction), 0)
    )
  ), '[]'::json)
  FROM stores st
  INNER JOIN assignments_promotor_store aps ON st.id = aps.store_id
  INNER JOIN promotor_ids pi ON aps.promotor_id = pi.promotor_id
  LEFT JOIN sell_out s ON s.store_id = st.id 
    AND TO_CHAR(s.sale_date AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') = v_period
  WHERE aps.active = true
  GROUP BY st.id, st.store_name
  ORDER BY COALESCE(SUM(s.quantity), 0) DESC;
END;
$$;

-- =====================================================
-- 7. SATOR SALES PER PROMOTOR
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_sales_per_promotor(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period TEXT;
BEGIN
  v_period := COALESCE(p_period, TO_CHAR(CURRENT_DATE, 'YYYY-MM'));
  
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'promotor_id', u.id,
      'promotor_name', u.full_name,
      'promotor_type', u.promotor_type,
      'total_units', COALESCE(SUM(s.quantity), 0),
      'total_revenue', COALESCE(SUM(s.price_at_transaction), 0)
    )
  ), '[]'::json)
  FROM users u
  INNER JOIN promotor_ids pi ON u.id = pi.promotor_id
  LEFT JOIN sell_out s ON s.promotor_id = u.id 
    AND TO_CHAR(s.sale_date AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') = v_period
  GROUP BY u.id, u.full_name, u.promotor_type
  ORDER BY COALESCE(SUM(s.quantity), 0) DESC;
END;
$$;

-- =====================================================
-- 8. SATOR AKTIVITAS TIM
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_aktivitas_tim(
  p_sator_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  store_data AS (
    SELECT DISTINCT
      st.id as store_id,
      st.store_name
    FROM stores st
    INNER JOIN assignments_promotor_store aps ON st.id = aps.store_id
    WHERE aps.promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND aps.active = true
  ),
  promotor_checklist AS (
    SELECT 
      u.id as promotor_id,
      u.full_name as name,
      aps.store_id,
      -- Check each activity
      EXISTS(SELECT 1 FROM attendance_logs al WHERE al.user_id = u.id AND DATE(al.clock_in AT TIME ZONE 'Asia/Makassar') = p_date) as clock_in,
      EXISTS(SELECT 1 FROM sell_out s WHERE s.promotor_id = u.id AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = p_date) as sell_out,
      EXISTS(SELECT 1 FROM stock_movement_log sm WHERE sm.promotor_id = u.id AND DATE(sm.created_at AT TIME ZONE 'Asia/Makassar') = p_date) as stock_input,
      EXISTS(SELECT 1 FROM promotion_reports pr WHERE pr.user_id = u.id AND DATE(pr.created_at AT TIME ZONE 'Asia/Makassar') = p_date) as promotion,
      EXISTS(SELECT 1 FROM follower_reports fr WHERE fr.user_id = u.id AND DATE(fr.created_at AT TIME ZONE 'Asia/Makassar') = p_date) as follower
    FROM users u
    INNER JOIN promotor_ids pi ON u.id = pi.promotor_id
    INNER JOIN assignments_promotor_store aps ON u.id = aps.promotor_id
    WHERE aps.active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', sd.store_id,
      'store_name', sd.store_name,
      'promotors', (
        SELECT COALESCE(json_agg(
          json_build_object(
            'id', pc.promotor_id,
            'name', pc.name,
            'clock_in', pc.clock_in,
            'sell_out', pc.sell_out,
            'stock_input', pc.stock_input,
            'promotion', pc.promotion,
            'follower', pc.follower
          )
        ), '[]'::json)
        FROM promotor_checklist pc
        WHERE pc.store_id = sd.store_id
      )
    )
  ), '[]'::json)
  FROM store_data sd;
END;
$$;

-- =====================================================
-- 9. TEAM LEADERBOARD
-- =====================================================
CREATE OR REPLACE FUNCTION get_team_leaderboard(
  p_sator_id UUID,
  p_period TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period TEXT;
BEGIN
  v_period := COALESCE(p_period, TO_CHAR(CURRENT_DATE, 'YYYY-MM'));
  
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(s.quantity), 0) DESC),
      'promotor_id', u.id,
      'promotor_name', u.full_name,
      'total_units', COALESCE(SUM(s.quantity), 0),
      'total_revenue', COALESCE(SUM(s.price_at_transaction), 0)
    )
  ), '[]'::json)
  FROM users u
  INNER JOIN promotor_ids pi ON u.id = pi.promotor_id
  LEFT JOIN sell_out s ON s.promotor_id = u.id 
    AND TO_CHAR(s.sale_date AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') = v_period
  GROUP BY u.id, u.full_name
  ORDER BY COALESCE(SUM(s.quantity), 0) DESC;
END;
$$;

-- =====================================================
-- 10. TEAM LIVE FEED
-- =====================================================
CREATE OR REPLACE FUNCTION get_team_live_feed(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', a.id,
      'type', a.activity_type,
      'user_id', a.user_id,
      'user_name', u.full_name,
      'message', a.message,
      'created_at', a.created_at
    ) ORDER BY a.created_at DESC
  ), '[]'::json)
  FROM activity_feed a
  INNER JOIN users u ON a.user_id = u.id
  WHERE a.user_id IN (SELECT promotor_id FROM promotor_ids)
  AND a.created_at > NOW() - INTERVAL '24 hours'
  LIMIT 50;
END;
$$;

-- =====================================================
-- 11. GUDANG STOCK (Warehouse)
-- =====================================================
CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Get stock from warehouse associated with SATOR's area
  WITH sator_area AS (
    SELECT area FROM users WHERE id = p_sator_id
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'product_id', p.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'qty', COALESCE(ws.quantity, 0),
      'category', CASE 
        WHEN COALESCE(ws.quantity, 0) >= 10 THEN 'plenty'
        WHEN COALESCE(ws.quantity, 0) >= 5 THEN 'enough'
        WHEN COALESCE(ws.quantity, 0) > 0 THEN 'critical'
        ELSE 'empty'
      END
    )
  ), '[]'::json)
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  LEFT JOIN warehouse_stock ws ON pv.id = ws.variant_id
  WHERE p.status = 'active' AND pv.active = true
  ORDER BY pv.srp ASC;
END;
$$;

-- =====================================================
-- 12. STORE STOCK STATUS
-- =====================================================
CREATE OR REPLACE FUNCTION get_store_stock_status(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
  FROM stores st
  WHERE st.id IN (SELECT store_id FROM store_ids);
END;
$$;

-- =====================================================
-- 13. REORDER RECOMMENDATIONS
-- =====================================================
CREATE OR REPLACE FUNCTION get_reorder_recommendations(
  p_sator_id UUID,
  p_store_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
    AND (p_store_id IS NULL OR store_id = p_store_id)
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'product_id', pv.id,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'color', pv.color,
      'price', pv.srp,
      'current_stock', COALESCE(si.quantity, 0),
      'reorder_qty', GREATEST(5 - COALESCE(si.quantity, 0), 0)
    )
  ), '[]'::json)
  FROM products p
  INNER JOIN product_variants pv ON p.id = pv.product_id
  CROSS JOIN store_ids sid
  LEFT JOIN store_inventory si ON pv.id = si.variant_id AND si.store_id = sid.store_id
  WHERE p.status = 'active' AND pv.active = true
  AND (COALESCE(si.quantity, 0) < 5)
  ORDER BY pv.srp ASC;
END;
$$;

-- =====================================================
-- 14. PENDING SCHEDULES
-- =====================================================
CREATE OR REPLACE FUNCTION get_pending_schedules(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', sr.id,
      'promotor_id', sr.user_id,
      'promotor_name', u.full_name,
      'type', sr.schedule_type,
      'date', sr.schedule_date,
      'reason', sr.reason,
      'status', sr.status,
      'created_at', sr.created_at
    ) ORDER BY sr.created_at DESC
  ), '[]'::json)
  FROM schedule_requests sr
  INNER JOIN users u ON sr.user_id = u.id
  WHERE sr.user_id IN (SELECT promotor_id FROM promotor_ids)
  AND sr.status = 'pending';
END;
$$;

-- =====================================================
-- 15. TEAM CALENDAR
-- =====================================================
CREATE OR REPLACE FUNCTION get_team_calendar(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', sr.id,
      'promotor_id', sr.user_id,
      'promotor_name', u.full_name,
      'type', sr.schedule_type,
      'date', sr.schedule_date,
      'status', sr.status
    )
  ), '[]'::json)
  FROM schedule_requests sr
  INNER JOIN users u ON sr.user_id = u.id
  WHERE sr.user_id IN (SELECT promotor_id FROM promotor_ids)
  AND sr.schedule_date >= CURRENT_DATE
  AND sr.status = 'approved'
  ORDER BY sr.schedule_date;
END;
$$;

-- =====================================================
-- 16. SATOR VISITING STORES
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_visiting_stores(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
      'address', st.address,
      'last_visit', (
        SELECT MAX(sv.created_at) FROM store_visits sv WHERE sv.store_id = st.id
      ),
      'issue_count', (
        SELECT COUNT(*) FROM store_issues si WHERE si.store_id = st.id AND si.resolved = false
      ),
      'priority', CASE
        WHEN (SELECT COUNT(*) FROM store_issues si WHERE si.store_id = st.id AND si.resolved = false) > 0 THEN 1
        WHEN (SELECT MAX(sv.created_at) FROM store_visits sv WHERE sv.store_id = st.id) IS NULL THEN 2
        WHEN (SELECT MAX(sv.created_at) FROM store_visits sv WHERE sv.store_id = st.id) < NOW() - INTERVAL '7 days' THEN 3
        ELSE 4
      END
    )
  ), '[]'::json)
  FROM stores st
  WHERE st.id IN (SELECT store_id FROM store_ids)
  ORDER BY CASE
    WHEN (SELECT COUNT(*) FROM store_issues si WHERE si.store_id = st.id AND si.resolved = false) > 0 THEN 1
    WHEN (SELECT MAX(sv.created_at) FROM store_visits sv WHERE sv.store_id = st.id) IS NULL THEN 2
    ELSE 3
  END;
END;
$$;

-- =====================================================
-- 17. STORE PROMOTOR CHECKLIST
-- =====================================================
CREATE OR REPLACE FUNCTION get_store_promotor_checklist(
  p_store_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', u.id,
      'name', u.full_name,
      'promotor_type', u.promotor_type,
      'clock_in', EXISTS(SELECT 1 FROM attendance_logs al WHERE al.user_id = u.id AND DATE(al.clock_in AT TIME ZONE 'Asia/Makassar') = p_date),
      'sell_out', EXISTS(SELECT 1 FROM sell_out s WHERE s.promotor_id = u.id AND DATE(s.sale_date AT TIME ZONE 'Asia/Makassar') = p_date),
      'stock_input', EXISTS(SELECT 1 FROM stock_movement_log sm WHERE sm.promotor_id = u.id AND DATE(sm.created_at AT TIME ZONE 'Asia/Makassar') = p_date),
      'promotion', EXISTS(SELECT 1 FROM promotion_reports pr WHERE pr.user_id = u.id AND DATE(pr.created_at AT TIME ZONE 'Asia/Makassar') = p_date),
      'follower', EXISTS(SELECT 1 FROM follower_reports fr WHERE fr.user_id = u.id AND DATE(fr.created_at AT TIME ZONE 'Asia/Makassar') = p_date),
      'allbrand', EXISTS(SELECT 1 FROM allbrand_reports ab WHERE ab.user_id = u.id AND DATE(ab.created_at AT TIME ZONE 'Asia/Makassar') = p_date),
      'stock_validation', EXISTS(SELECT 1 FROM stock_validations sv WHERE sv.promotor_id = u.id AND DATE(sv.created_at AT TIME ZONE 'Asia/Makassar') = p_date)
    )
  ), '[]'::json)
  FROM users u
  INNER JOIN assignments_promotor_store aps ON u.id = aps.promotor_id
  WHERE aps.store_id = p_store_id
  AND aps.active = true
  AND u.status = 'active';
END;
$$;

-- =====================================================
-- 18. SATOR KPI DETAIL
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_kpi_detail(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_month TEXT;
BEGIN
  v_current_month := TO_CHAR(CURRENT_DATE, 'YYYY-MM');
  
  SELECT json_build_object(
    'sell_out_all', COALESCE(sell_out_all_score, 0),
    'sell_out_fokus', COALESCE(sell_out_fokus_score, 0),
    'sell_in', COALESCE(sell_in_score, 0),
    'kpi_ma', COALESCE(kpi_ma_score, 0),
    'total_score', COALESCE(total_score, 0)
  )
  FROM sator_monthly_kpi
  WHERE sator_id = p_sator_id
  AND period_month = v_current_month;
END;
$$;

-- =====================================================
-- 19. SATOR PERFORMANCE PER TOKO
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_performance_per_toko(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', st.id,
      'store_name', st.store_name,
      'total_units', COALESCE(SUM(s.quantity), 0),
      'total_revenue', COALESCE(SUM(s.price_at_transaction), 0)
    )
  ), '[]'::json)
  FROM stores st
  INNER JOIN assignments_promotor_store aps ON st.id = aps.store_id
  INNER JOIN promotor_ids pi ON aps.promotor_id = pi.promotor_id
  LEFT JOIN sell_out s ON s.store_id = st.id 
    AND TO_CHAR(s.sale_date AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') = TO_CHAR(CURRENT_DATE, 'YYYY-MM')
  WHERE aps.active = true
  GROUP BY st.id, st.store_name
  ORDER BY COALESCE(SUM(s.quantity), 0) DESC;
END;
$$;

-- =====================================================
-- 20. SATOR REWARDS
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_rewards(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', sr.id,
      'name', sr.reward_name,
      'amount', sr.amount,
      'period', sr.period_month,
      'status', sr.status,
      'paid_date', sr.paid_date
    ) ORDER BY sr.created_at DESC
  ), '[]'::json)
  FROM sator_rewards sr
  WHERE sr.sator_id = p_sator_id;
END;
$$;

-- =====================================================
-- 21. SATOR REWARD HISTORY
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_reward_history(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', sr.id,
      'name', sr.reward_name,
      'amount', sr.amount,
      'period', sr.period_month,
      'status', sr.status,
      'paid_date', sr.paid_date
    ) ORDER BY sr.created_at DESC
  ), '[]'::json)
  FROM sator_rewards sr
  WHERE sr.sator_id = p_sator_id;
END;
$$;

-- =====================================================
-- 22. SATOR IMEI LIST
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_imei_list(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', i.id,
      'imei', i.imei_number,
      'product_name', p.model_name,
      'variant', pv.ram_rom,
      'status', i.normalization_status,
      'promotor_name', u.full_name,
      'store_name', st.store_name,
      'created_at', i.created_at
    ) ORDER BY i.created_at DESC
  ), '[]'::json)
  FROM imei_records i
  INNER JOIN users u ON i.promotor_id = u.id
  INNER JOIN stores st ON i.store_id = st.id
  INNER JOIN product_variants pv ON i.variant_id = pv.id
  INNER JOIN products p ON pv.product_id = p.id
  WHERE i.promotor_id IN (SELECT promotor_id FROM promotor_ids)
  AND i.normalization_status != 'completed'
  LIMIT 100;
END;
$$;

-- =====================================================
-- 23. SELLIN ACHIEVEMENT
-- =====================================================
CREATE OR REPLACE FUNCTION get_sellin_achievement(
  p_sator_id UUID,
  p_view_mode TEXT DEFAULT 'daily'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_view_mode = 'daily' THEN
    RETURN (
      SELECT COALESCE(json_agg(
        json_build_object(
          'date', DATE(si.created_at AT TIME ZONE 'Asia/Makassar'),
          'total_units', SUM(si.quantity),
          'total_value', SUM(si.total_price)
        )
      ), '[]'::json)
      FROM sell_in si
      WHERE si.sator_id = p_sator_id
      AND si.created_at >= CURRENT_DATE - INTERVAL '30 days'
      GROUP BY DATE(si.created_at AT TIME ZONE 'Asia/Makassar')
      ORDER BY DATE(si.created_at AT TIME ZONE 'Asia/Makassar') DESC
    );
  ELSE
    RETURN (
      SELECT COALESCE(json_agg(
        json_build_object(
          'date', TO_CHAR(si.created_at AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') || '-01',
          'total_units', SUM(si.quantity),
          'total_value', SUM(si.total_price)
        )
      ), '[]'::json)
      FROM sell_in si
      WHERE si.sator_id = p_sator_id
      AND si.created_at >= CURRENT_DATE - INTERVAL '12 months'
      GROUP BY TO_CHAR(si.created_at AT TIME ZONE 'Asia/Makassar', 'YYYY-MM')
      ORDER BY TO_CHAR(si.created_at AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') DESC
    );
  END IF;
END;
$$;

-- =====================================================
-- 24. PENDING ORDERS
-- =====================================================
CREATE OR REPLACE FUNCTION get_pending_orders(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', o.id,
      'store_name', st.store_name,
      'total_items', o.total_items,
      'total_value', o.total_value,
      'status', o.status,
      'created_at', o.created_at
    ) ORDER BY o.created_at DESC
  ), '[]'::json)
  FROM orders o
  INNER JOIN stores st ON o.store_id = st.id
  WHERE o.sator_id = p_sator_id
  AND o.status = 'pending';
END;
$$;

-- =====================================================
-- 25. SATOR SELLIN SUMMARY
-- =====================================================
CREATE OR REPLACE FUNCTION get_sator_sellin_summary(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_month TEXT;
BEGIN
  v_current_month := TO_CHAR(CURRENT_DATE, 'YYYY-MM');
  
  SELECT json_build_object(
    'monthly_units', COALESCE(SUM(si.quantity), 0),
    'monthly_value', COALESCE(SUM(si.total_price), 0),
    'today_units', COALESCE(SUM(CASE WHEN DATE(si.created_at AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE THEN si.quantity ELSE 0 END), 0),
    'today_value', COALESCE(SUM(CASE WHEN DATE(si.created_at AT TIME ZONE 'Asia/Makassar') = CURRENT_DATE THEN si.total_price ELSE 0 END), 0)
  )
  FROM sell_in si
  WHERE si.sator_id = p_sator_id
  AND TO_CHAR(si.created_at AT TIME ZONE 'Asia/Makassar', 'YYYY-MM') = v_current_month;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
