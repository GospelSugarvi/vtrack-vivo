with ranked_active_periods as (
  select
    id,
    row_number() over (
      order by
        target_year desc nulls last,
        target_month desc nulls last,
        start_date desc nulls last,
        created_at desc
    ) as rn
  from public.target_periods
  where status = 'active'
    and deleted_at is null
)
update public.target_periods tp
set
  status = 'inactive',
  updated_at = now()
from ranked_active_periods rap
where tp.id = rap.id
  and rap.rn > 1;

create unique index if not exists target_periods_single_active_idx
on public.target_periods ((status))
where status = 'active' and deleted_at is null;
