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
  v_enriched_sator_cards jsonb := '[]'::jsonb;
  v_week_start date := p_date - (extract(isodow from p_date)::int - 1);
  v_month_key date := date_trunc('month', p_date)::date;
  v_month_start date := date_trunc('month', p_date)::date;
  v_period_id uuid;
  v_active_week_percentage numeric := 25;
begin
  v_base := coalesce(
    public.get_spv_home_snapshot_base(p_spv_id, p_date),
    '{}'::jsonb
  );

  select tp.id
  into v_period_id
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
  order by tp.start_date desc
  limit 1;

  if v_period_id is not null then
    select wt.percentage
    into v_active_week_percentage
    from public.weekly_targets wt
    where wt.period_id = v_period_id
      and extract(day from p_date)::int between wt.start_day and wt.end_day
    order by wt.week_number
    limit 1;
  end if;

  v_active_week_percentage := coalesce(v_active_week_percentage, 25);

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

  with base_cards as (
    select
      card,
      ordinality,
      nullif(card ->> 'sator_id', '')::uuid as sator_id
    from jsonb_array_elements(coalesce(v_base -> 'sator_cards', '[]'::jsonb))
      with ordinality as t(card, ordinality)
  ),
  sellin_targets as (
    select
      bc.sator_id,
      coalesce(ut.target_sell_in, 0)::numeric as target_sell_in_monthly
    from base_cards bc
    left join public.user_targets ut
      on ut.user_id = bc.sator_id
     and ut.period_id = v_period_id
  ),
  sellin_actuals as (
    select
      bc.sator_id,
      coalesce(sum(case when o.order_date = p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_daily,
      coalesce(sum(case when o.order_date between v_week_start and p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_weekly,
      coalesce(sum(case when o.order_date between v_month_start and p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_monthly
    from base_cards bc
    left join public.sell_in_orders o
      on o.sator_id = bc.sator_id
     and o.status = 'finalized'
     and o.order_date between v_month_start and p_date
    group by bc.sator_id
  ),
  merged as (
    select
      bc.ordinality,
      bc.card ||
        jsonb_build_object(
          'target_sell_in_daily', round((coalesce(st.target_sell_in_monthly, 0) * v_active_week_percentage / 100.0) / 6.0),
          'target_sell_in_weekly', round(coalesce(st.target_sell_in_monthly, 0) * v_active_week_percentage / 100.0),
          'target_sell_in_monthly', round(coalesce(st.target_sell_in_monthly, 0)),
          'actual_sell_in_daily', round(coalesce(sa.actual_sell_in_daily, 0)),
          'actual_sell_in_weekly', round(coalesce(sa.actual_sell_in_weekly, 0)),
          'actual_sell_in_monthly', round(coalesce(sa.actual_sell_in_monthly, 0))
        ) as card
    from base_cards bc
    left join sellin_targets st on st.sator_id = bc.sator_id
    left join sellin_actuals sa on sa.sator_id = bc.sator_id
  )
  select coalesce(jsonb_agg(card order by ordinality), '[]'::jsonb)
  into v_enriched_sator_cards
  from merged;

  return v_base || jsonb_build_object(
    'sator_cards', coalesce(v_enriched_sator_cards, '[]'::jsonb),
    'vast_daily', coalesce(v_vast_daily, '{}'::jsonb),
    'vast_weekly', coalesce(v_vast_weekly, '{}'::jsonb),
    'vast_monthly', coalesce(v_vast_monthly, '{}'::jsonb)
  );
end;
$function$;

grant execute on function public.get_spv_home_snapshot(uuid, date)
to authenticated;
