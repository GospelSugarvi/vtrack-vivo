do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_spv_home_snapshot_base'
      and pg_get_function_identity_arguments(p.oid) = 'p_spv_id uuid, p_date date'
  ) then
    null;
  elsif exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_spv_home_snapshot'
      and pg_get_function_identity_arguments(p.oid) = 'p_spv_id uuid, p_date date'
  ) then
    alter function public.get_spv_home_snapshot(uuid, date)
      rename to get_spv_home_snapshot_base;
  else
    raise exception
      'Function public.get_spv_home_snapshot(uuid, date) not found';
  end if;
end
$$;

create or replace function public.get_spv_home_snapshot(
  p_spv_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_base jsonb := '{}'::jsonb;
  v_vast_daily jsonb := '{}'::jsonb;
  v_vast_weekly jsonb := '{}'::jsonb;
  v_vast_monthly jsonb := '{}'::jsonb;
  v_week_start date := p_date - (extract(isodow from p_date)::int - 1);
  v_month_key date := date_trunc('month', p_date)::date;
begin
  v_base := coalesce(
    public.get_spv_home_snapshot_base(p_spv_id, p_date),
    '{}'::jsonb
  );

  select to_jsonb(vd.*)
  into v_vast_daily
  from public.vast_agg_daily_spv vd
  where vd.spv_id = p_spv_id
    and vd.metric_date = p_date
  limit 1;

  select to_jsonb(vw.*)
  into v_vast_weekly
  from public.vast_agg_weekly_spv vw
  where vw.spv_id = p_spv_id
    and vw.week_start_date = v_week_start
  limit 1;

  select to_jsonb(vm.*)
  into v_vast_monthly
  from public.vast_agg_monthly_spv vm
  where vm.spv_id = p_spv_id
    and vm.month_key = v_month_key
  limit 1;

  return v_base || jsonb_build_object(
    'vast_daily', coalesce(v_vast_daily, '{}'::jsonb),
    'vast_weekly', coalesce(v_vast_weekly, '{}'::jsonb),
    'vast_monthly', coalesce(v_vast_monthly, '{}'::jsonb)
  );
end;
$function$;

grant execute on function public.get_spv_home_snapshot(uuid, date)
to authenticated;
