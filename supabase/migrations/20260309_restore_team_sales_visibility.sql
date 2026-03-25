-- Restore team/area visibility on sales_sell_out for SATOR and SPV.
-- Needed so chip sale history can be tracked outside the promotor account.

ALTER TABLE IF EXISTS public.sales_sell_out ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sator Team Sales Read" ON public.sales_sell_out;
CREATE POLICY "Sator Team Sales Read"
ON public.sales_sell_out
FOR SELECT
USING (
  promotor_id IN (
    SELECT hsp.promotor_id
    FROM public.hierarchy_sator_promotor hsp
    WHERE hsp.sator_id = auth.uid()
      AND hsp.active = true
  )
);

DROP POLICY IF EXISTS "SPV Area Sales Read" ON public.sales_sell_out;
CREATE POLICY "SPV Area Sales Read"
ON public.sales_sell_out
FOR SELECT
USING (
  promotor_id IN (
    SELECT hsp.promotor_id
    FROM public.hierarchy_sator_promotor hsp
    JOIN public.hierarchy_spv_sator hss
      ON hss.sator_id = hsp.sator_id
    WHERE hss.spv_id = auth.uid()
      AND hss.active = true
      AND hsp.active = true
  )
);

DROP POLICY IF EXISTS "Admin All Sales Read" ON public.sales_sell_out;
CREATE POLICY "Admin All Sales Read"
ON public.sales_sell_out
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid()
      AND u.role = 'admin'
  )
);
