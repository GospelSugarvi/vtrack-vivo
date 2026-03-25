-- Fill missing store group assignments with a neutral fallback group.
-- This avoids null group_id in sell-in/order flows without forcing
-- speculative business grouping into existing named groups.

INSERT INTO public.store_groups (group_name, is_spc, owner_name)
VALUES ('UNGROUPED KUPANG', false, NULL)
ON CONFLICT (group_name) DO NOTHING;

UPDATE public.stores
SET group_id = (
  SELECT sg.id
  FROM public.store_groups sg
  WHERE sg.group_name = 'UNGROUPED KUPANG'
    AND sg.deleted_at IS NULL
  LIMIT 1
)
WHERE deleted_at IS NULL
  AND group_id IS NULL
  AND UPPER(COALESCE(area, '')) = 'KUPANG';

UPDATE public.sell_in_orders o
SET group_id = st.group_id
FROM public.stores st
WHERE o.store_id = st.id
  AND o.group_id IS NULL
  AND st.group_id IS NOT NULL;

UPDATE public.sales_sell_in si
SET group_id = COALESCE(si.group_id, st.group_id)
FROM public.stores st
WHERE si.store_id = st.id
  AND si.deleted_at IS NULL
  AND si.group_id IS NULL
  AND st.group_id IS NOT NULL;
