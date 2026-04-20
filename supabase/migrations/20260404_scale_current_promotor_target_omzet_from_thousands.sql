update public.user_targets ut
set
  target_omzet = ut.target_omzet * 1000,
  updated_at = now()
from public.users u
where ut.user_id = u.id
  and u.role = 'promotor'
  and ut.target_omzet between 1 and 999999
  and ut.period_id = (
    select tp.id
    from public.target_periods tp
    where current_date between tp.start_date and tp.end_date
      and tp.deleted_at is null
    order by tp.start_date desc, tp.created_at desc
    limit 1
  );
