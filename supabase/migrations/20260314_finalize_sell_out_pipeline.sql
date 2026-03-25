-- Finalize sell-out pipeline hardening.
-- 1. Backfill missing status history for legacy sales rows.
-- 2. Remove direct INSERT policy so sales writes must go through process_sell_out_atomic.

INSERT INTO public.sales_sell_out_status_history (
  sales_sell_out_id,
  old_status,
  new_status,
  notes,
  changed_by,
  changed_at
)
SELECT
  so.id,
  NULL,
  COALESCE(so.status, 'verified'),
  'Backfilled for legacy sell-out row',
  so.promotor_id,
  COALESCE(so.created_at, NOW())
FROM public.sales_sell_out so
LEFT JOIN public.sales_sell_out_status_history h
  ON h.sales_sell_out_id = so.id
WHERE so.deleted_at IS NULL
  AND h.sales_sell_out_id IS NULL;

DROP POLICY IF EXISTS "Sales insert own" ON public.sales_sell_out;
