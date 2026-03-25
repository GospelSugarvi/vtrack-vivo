-- Allow promotors to detect stock rows that are waiting to be claimed.
-- This is intentionally SELECT-only and scoped to unsold pending-claim rows.

DROP POLICY IF EXISTS "Promotor can read pending claim stock" ON public.stok;

CREATE POLICY "Promotor can read pending claim stock"
ON public.stok
FOR SELECT
USING (
  is_sold = false
  AND store_id IS NULL
  AND relocation_status = 'pending_claim'
  AND EXISTS (
    SELECT 1
    FROM public.assignments_promotor_store aps
    WHERE aps.promotor_id = auth.uid()
      AND aps.active = true
  )
);
