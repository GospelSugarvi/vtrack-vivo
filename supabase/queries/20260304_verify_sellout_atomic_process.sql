-- =====================================================
-- VERIFY: Sell Out Atomic Process
-- Date: 2026-03-04
-- Purpose:
-- 1) Verify consistency sales_sell_out <-> stok <-> stock_movement_log
-- 2) Detect anomalies after migration process_sell_out_atomic
-- =====================================================

-- 0) Summary volume (recent 30 days)
SELECT
  'SUMMARY_LAST_30_DAYS' AS section,
  COUNT(*)::INT AS sellout_rows,
  COUNT(DISTINCT serial_imei)::INT AS unique_imei,
  COALESCE(SUM(price_at_transaction), 0)::NUMERIC AS total_revenue
FROM public.sales_sell_out
WHERE transaction_date >= CURRENT_DATE - INTERVAL '30 days';

-- 1) Sales rows whose IMEI not found in stok
SELECT
  'SALES_IMEI_NOT_IN_STOK' AS section,
  s.id AS sale_id,
  s.serial_imei,
  s.promotor_id,
  s.transaction_date,
  s.created_at
FROM public.sales_sell_out s
LEFT JOIN public.stok st ON st.imei = s.serial_imei
WHERE st.id IS NULL
ORDER BY s.created_at DESC
LIMIT 200;

-- 2) Sales rows where stok exists but not marked sold
SELECT
  'SALES_STOK_NOT_SOLD' AS section,
  s.id AS sale_id,
  s.serial_imei,
  s.promotor_id,
  s.transaction_date,
  st.id AS stok_id,
  st.is_sold,
  st.sold_at,
  st.sold_price,
  s.created_at
FROM public.sales_sell_out s
JOIN public.stok st ON st.imei = s.serial_imei
WHERE COALESCE(st.is_sold, false) = false
ORDER BY s.created_at DESC
LIMIT 200;

-- 3) Price mismatch between sales_sell_out and stok.sold_price
SELECT
  'SALES_STOK_PRICE_MISMATCH' AS section,
  s.id AS sale_id,
  s.serial_imei,
  s.price_at_transaction AS sale_price,
  st.sold_price,
  s.created_at
FROM public.sales_sell_out s
JOIN public.stok st ON st.imei = s.serial_imei
WHERE st.sold_price IS DISTINCT FROM s.price_at_transaction
ORDER BY s.created_at DESC
LIMIT 200;

-- 4) Missing sold movement log for each sale
SELECT
  'SALES_MISSING_MOVEMENT_LOG' AS section,
  s.id AS sale_id,
  s.serial_imei,
  s.promotor_id,
  s.transaction_date,
  s.created_at
FROM public.sales_sell_out s
WHERE NOT EXISTS (
  SELECT 1
  FROM public.stock_movement_log m
  WHERE m.imei = s.serial_imei
    AND m.movement_type = 'sold'
    AND m.moved_by = s.promotor_id
)
ORDER BY s.created_at DESC
LIMIT 200;

-- 5) Duplicate sold movement logs (same IMEI + promotor)
SELECT
  'DUPLICATE_MOVEMENT_LOG' AS section,
  m.imei,
  m.moved_by,
  COUNT(*)::INT AS sold_log_count,
  MIN(m.moved_at) AS first_log_at,
  MAX(m.moved_at) AS last_log_at
FROM public.stock_movement_log m
WHERE m.movement_type = 'sold'
GROUP BY m.imei, m.moved_by
HAVING COUNT(*) > 1
ORDER BY sold_log_count DESC, last_log_at DESC
LIMIT 200;

-- 6) Duplicate sell_out row by IMEI (should be impossible because serial_imei UNIQUE)
SELECT
  'DUPLICATE_SALES_IMEI' AS section,
  serial_imei,
  COUNT(*)::INT AS sales_count,
  MIN(created_at) AS first_sale_at,
  MAX(created_at) AS last_sale_at
FROM public.sales_sell_out
GROUP BY serial_imei
HAVING COUNT(*) > 1
ORDER BY sales_count DESC, last_sale_at DESC
LIMIT 200;

-- 7) Business rule checks: kredit must have leasing_provider
SELECT
  'KREDIT_WITHOUT_LEASING' AS section,
  s.id AS sale_id,
  s.serial_imei,
  s.payment_method,
  s.leasing_provider,
  s.created_at
FROM public.sales_sell_out s
WHERE s.payment_method = 'kredit'
  AND COALESCE(s.leasing_provider, '') = ''
ORDER BY s.created_at DESC
LIMIT 200;

-- 8) Customer type whitelist sanity
SELECT
  'INVALID_CUSTOMER_TYPE' AS section,
  s.id AS sale_id,
  s.serial_imei,
  s.customer_type,
  s.created_at
FROM public.sales_sell_out s
WHERE COALESCE(s.customer_type, '') NOT IN ('toko', 'vip_call')
ORDER BY s.created_at DESC
LIMIT 200;

-- 9) Optional quick status counters for anomaly sections
WITH anomaly_counts AS (
  SELECT 'SALES_IMEI_NOT_IN_STOK' AS check_name, COUNT(*)::INT AS cnt
  FROM public.sales_sell_out s
  LEFT JOIN public.stok st ON st.imei = s.serial_imei
  WHERE st.id IS NULL

  UNION ALL
  SELECT 'SALES_STOK_NOT_SOLD', COUNT(*)::INT
  FROM public.sales_sell_out s
  JOIN public.stok st ON st.imei = s.serial_imei
  WHERE COALESCE(st.is_sold, false) = false

  UNION ALL
  SELECT 'SALES_STOK_PRICE_MISMATCH', COUNT(*)::INT
  FROM public.sales_sell_out s
  JOIN public.stok st ON st.imei = s.serial_imei
  WHERE st.sold_price IS DISTINCT FROM s.price_at_transaction

  UNION ALL
  SELECT 'SALES_MISSING_MOVEMENT_LOG', COUNT(*)::INT
  FROM public.sales_sell_out s
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.stock_movement_log m
    WHERE m.imei = s.serial_imei
      AND m.movement_type = 'sold'
      AND m.moved_by = s.promotor_id
  )
)
SELECT
  'ANOMALY_COUNTS' AS section,
  check_name,
  cnt
FROM anomaly_counts
ORDER BY check_name;
