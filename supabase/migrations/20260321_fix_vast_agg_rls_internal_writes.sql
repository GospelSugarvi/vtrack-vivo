set check_function_bodies = off;

create or replace function public.vast_refresh_rollups_after_application()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if tg_op = 'DELETE' then
    perform public.vast_refresh_rollups_for_scope(
      old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.month_key, old.period_id
    );
    perform public.vast_refresh_weekly_rollups_for_scope(
      old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.period_id
    );
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.promotor_id is distinct from new.promotor_id
       or old.sator_id is distinct from new.sator_id
       or old.spv_id is distinct from new.spv_id
       or old.application_date is distinct from new.application_date
       or old.month_key is distinct from new.month_key
       or old.period_id is distinct from new.period_id then
      perform public.vast_refresh_rollups_for_scope(
        old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.month_key, old.period_id
      );
      perform public.vast_refresh_weekly_rollups_for_scope(
        old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.period_id
      );
    end if;
  end if;

  perform public.vast_refresh_rollups_for_scope(
    new.promotor_id, new.sator_id, new.spv_id, new.application_date, new.month_key, new.period_id
  );
  perform public.vast_refresh_weekly_rollups_for_scope(
    new.promotor_id, new.sator_id, new.spv_id, new.application_date, new.period_id
  );
  return new;
end;
$function$;

drop policy if exists "vast agg daily promotor internal write" on public.vast_agg_daily_promotor;
create policy "vast agg daily promotor internal write"
on public.vast_agg_daily_promotor
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg monthly promotor internal write" on public.vast_agg_monthly_promotor;
create policy "vast agg monthly promotor internal write"
on public.vast_agg_monthly_promotor
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg daily sator internal write" on public.vast_agg_daily_sator;
create policy "vast agg daily sator internal write"
on public.vast_agg_daily_sator
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg monthly sator internal write" on public.vast_agg_monthly_sator;
create policy "vast agg monthly sator internal write"
on public.vast_agg_monthly_sator
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg daily spv internal write" on public.vast_agg_daily_spv;
create policy "vast agg daily spv internal write"
on public.vast_agg_daily_spv
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg monthly spv internal write" on public.vast_agg_monthly_spv;
create policy "vast agg monthly spv internal write"
on public.vast_agg_monthly_spv
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg weekly promotor internal write" on public.vast_agg_weekly_promotor;
create policy "vast agg weekly promotor internal write"
on public.vast_agg_weekly_promotor
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg weekly sator internal write" on public.vast_agg_weekly_sator;
create policy "vast agg weekly sator internal write"
on public.vast_agg_weekly_sator
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast agg weekly spv internal write" on public.vast_agg_weekly_spv;
create policy "vast agg weekly spv internal write"
on public.vast_agg_weekly_spv
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');
