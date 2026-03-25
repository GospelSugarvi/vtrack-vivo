-- Allow promotors to read movement logs for stock that is waiting to be claimed.
-- Needed so the receiving promotor can see origin store/promotor context in claim dialog.

DROP POLICY IF EXISTS "Promotor read pending claim movement" ON public.stock_movement_log;

CREATE POLICY "Promotor read pending claim movement"
ON public.stock_movement_log
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.stok s
    JOIN public.assignments_promotor_store aps
      ON aps.promotor_id = auth.uid()
     AND aps.active = true
    WHERE s.id = stock_movement_log.stok_id
      AND s.is_sold = false
      AND s.store_id IS NULL
      AND s.relocation_status = 'pending_claim'
  )
);
