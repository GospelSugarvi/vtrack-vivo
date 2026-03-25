-- =====================================================
-- SELL IN FINALIZATION GUARDRAIL AUDIT
-- Date: 2026-03-04
-- Purpose:
-- 1) Ensure pending/finalized status consistency in sell_in_orders
-- 2) Ensure header totals match sell_in_order_items aggregation
-- 3) Ensure finalized orders are synchronized to sales_sell_in feed
-- =====================================================

-- 0) Summary counts
SELECT
  'SUMMARY_STATUS_COUNTS' AS section,
  COUNT(*) FILTER (WHERE o.status = 'pending') AS pending_orders,
  COUNT(*) FILTER (WHERE o.status = 'finalized') AS finalized_orders,
  COUNT(*) FILTER (WHERE o.status = 'cancelled') AS cancelled_orders,
  COUNT(*) AS all_orders
FROM public.sell_in_orders o;

-- 1) Status timestamp consistency checks
SELECT
  'STATUS_INCONSISTENT_PENDING_HAS_FINALIZED_AT' AS section,
  o.id AS order_id,
  o.sator_id,
  o.store_id,
  o.order_date,
  o.status,
  o.finalized_at,
  o.finalized_by,
  o.updated_at
FROM public.sell_in_orders o
WHERE o.status = 'pending'
  AND (o.finalized_at IS NOT NULL OR o.finalized_by IS NOT NULL)
ORDER BY o.updated_at DESC;

SELECT
  'STATUS_INCONSISTENT_FINALIZED_MISSING_METADATA' AS section,
  o.id AS order_id,
  o.sator_id,
  o.store_id,
  o.order_date,
  o.status,
  o.finalized_at,
  o.finalized_by,
  o.updated_at
FROM public.sell_in_orders o
WHERE o.status = 'finalized'
  AND (o.finalized_at IS NULL OR o.finalized_by IS NULL)
ORDER BY o.updated_at DESC;

-- 2) Header vs item aggregation consistency
WITH item_agg AS (
  SELECT
    i.order_id,
    COUNT(*)::INT AS item_count,
    COALESCE(SUM(i.qty), 0)::INT AS total_qty,
    COALESCE(SUM(i.subtotal), 0)::NUMERIC AS total_value
  FROM public.sell_in_order_items i
  GROUP BY i.order_id
)
SELECT
  'HEADER_ITEM_MISMATCH' AS section,
  o.id AS order_id,
  o.status,
  o.total_items AS header_total_items,
  COALESCE(a.item_count, 0) AS item_total_items,
  o.total_qty AS header_total_qty,
  COALESCE(a.total_qty, 0) AS item_total_qty,
  o.total_value AS header_total_value,
  COALESCE(a.total_value, 0) AS item_total_value,
  o.updated_at
FROM public.sell_in_orders o
LEFT JOIN item_agg a ON a.order_id = o.id
WHERE o.total_items <> COALESCE(a.item_count, 0)
   OR o.total_qty <> COALESCE(a.total_qty, 0)
   OR o.total_value <> COALESCE(a.total_value, 0)
ORDER BY o.updated_at DESC;

-- 3) Finalized order must have feed row(s) in sales_sell_in
WITH feed_agg AS (
  SELECT
    (regexp_match(
      s.notes,
      'Finalized order #([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    ))[1]::UUID AS order_id,
    COUNT(*)::INT AS feed_rows,
    COALESCE(SUM(s.qty), 0)::INT AS feed_qty,
    COALESCE(SUM(s.total_value), 0)::NUMERIC AS feed_value
  FROM public.sales_sell_in s
  WHERE s.notes ~ 'Finalized order #[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  GROUP BY 1
)
SELECT
  'FINALIZED_MISSING_FEED' AS section,
  o.id AS order_id,
  o.sator_id,
  o.store_id,
  o.order_date,
  o.total_items,
  o.total_qty,
  o.total_value,
  o.finalized_at
FROM public.sell_in_orders o
LEFT JOIN feed_agg f ON f.order_id = o.id
WHERE o.status = 'finalized'
  AND f.order_id IS NULL
ORDER BY o.finalized_at DESC NULLS LAST;

-- 4) Finalized feed totals mismatch (duplicate/missing insert detector)
WITH feed_agg AS (
  SELECT
    (regexp_match(
      s.notes,
      'Finalized order #([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    ))[1]::UUID AS order_id,
    COUNT(*)::INT AS feed_rows,
    COALESCE(SUM(s.qty), 0)::INT AS feed_qty,
    COALESCE(SUM(s.total_value), 0)::NUMERIC AS feed_value
  FROM public.sales_sell_in s
  WHERE s.notes ~ 'Finalized order #[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  GROUP BY 1
)
SELECT
  'FINALIZED_FEED_MISMATCH' AS section,
  o.id AS order_id,
  o.total_items AS header_total_items,
  COALESCE(f.feed_rows, 0) AS feed_rows,
  o.total_qty AS header_total_qty,
  COALESCE(f.feed_qty, 0) AS feed_total_qty,
  o.total_value AS header_total_value,
  COALESCE(f.feed_value, 0) AS feed_total_value,
  o.finalized_at
FROM public.sell_in_orders o
LEFT JOIN feed_agg f ON f.order_id = o.id
WHERE o.status = 'finalized'
  AND (
    o.total_items <> COALESCE(f.feed_rows, 0)
    OR o.total_qty <> COALESCE(f.feed_qty, 0)
    OR o.total_value <> COALESCE(f.feed_value, 0)
  )
ORDER BY o.finalized_at DESC NULLS LAST;

-- 5) Optional focused view: by sator for quick triage
SELECT
  'SUMMARY_BY_SATOR' AS section,
  o.sator_id,
  COUNT(*) FILTER (WHERE o.status = 'pending') AS pending_orders,
  COUNT(*) FILTER (WHERE o.status = 'finalized') AS finalized_orders,
  COALESCE(SUM(o.total_qty) FILTER (WHERE o.status = 'finalized'), 0) AS finalized_qty,
  COALESCE(SUM(o.total_value) FILTER (WHERE o.status = 'finalized'), 0) AS finalized_value
FROM public.sell_in_orders o
GROUP BY o.sator_id
ORDER BY finalized_value DESC, finalized_qty DESC;
