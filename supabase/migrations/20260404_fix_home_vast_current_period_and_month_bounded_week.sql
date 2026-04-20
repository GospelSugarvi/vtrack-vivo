update public.target_periods
set status = case
  when current_date between start_date and end_date then 'active'
  else 'inactive'
end
where deleted_at is null;

create or replace function public.get_sator_home_snapshot(p_sator_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_profile jsonb := '{}'::jsonb;
  v_summary jsonb := '{}'::jsonb;
  v_promotor_cards jsonb := '{}'::jsonb;
  v_focus_products jsonb := '[]'::jsonb;
  v_today date := current_date;
  v_month_key date := date_trunc('month', current_date)::date;
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_number integer := 1;
  v_week_start_day integer := 1;
  v_week_end_day integer := 7;
  v_week_start date;
  v_week_end date;
  v_week_percentage numeric := 25;
  v_target_vast numeric := 0;
  v_vast_daily jsonb := '{}'::jsonb;
  v_vast_weekly jsonb := '{}'::jsonb;
  v_vast_monthly jsonb := '{}'::jsonb;
begin
  select jsonb_build_object(
    'nickname', nullif(trim(coalesce(u.nickname, '')), ''),
    'full_name', coalesce(u.full_name, 'SATOR'),
    'area', coalesce(u.area, '-'),
    'role', 'SATOR'
  )
  into v_profile
  from public.users u
  where u.id = p_sator_id;

  v_summary := coalesce(public.get_sator_home_summary(p_sator_id)::jsonb, '{}'::jsonb);
  v_promotor_cards := coalesce(public.get_sator_home_promotor_cards(p_sator_id)::jsonb, '{}'::jsonb);

  v_period_id := nullif(coalesce(v_summary #>> '{period,id}', ''), '')::uuid;

  if v_period_id is not null then
    select coalesce(jsonb_agg(to_jsonb(fp)), '[]'::jsonb)
    into v_focus_products
    from public.get_fokus_products_by_period(v_period_id) fp;
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where v_today between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is not null then
    v_week_number := greatest(least(((extract(day from v_today)::int - 1) / 7)::int + 1, 4), 1);

    select
      coalesce(wt.start_day, ((v_week_number - 1) * 7) + 1),
      coalesce(
        wt.end_day,
        case
          when v_week_number < 4 then v_week_number * 7
          else extract(day from v_period_end)::int
        end
      ),
      coalesce(wt.percentage, 25)
    into v_week_start_day, v_week_end_day, v_week_percentage
    from public.weekly_targets wt
    where wt.period_id = v_period_id
      and wt.week_number = v_week_number;

    v_week_start_day := coalesce(v_week_start_day, ((v_week_number - 1) * 7) + 1);
    v_week_end_day := coalesce(
      v_week_end_day,
      case
        when v_week_number < 4 then v_week_number * 7
        else extract(day from v_period_end)::int
      end
    );
    v_week_percentage := coalesce(v_week_percentage, 25);

    v_week_start := greatest(v_period_start, v_period_start + (v_week_start_day - 1));
    v_week_end := least(v_period_end, v_period_start + (v_week_end_day - 1));

    select coalesce(ut.target_vast, 0)
    into v_target_vast
    from public.user_targets ut
    where ut.user_id = p_sator_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc nulls last
    limit 1;
  else
    v_week_start := v_month_key;
    v_week_end := v_today;
  end if;

  select to_jsonb(vd.*)
  into v_vast_daily
  from public.vast_agg_daily_sator vd
  where vd.sator_id = p_sator_id
    and vd.metric_date = v_today
  limit 1;

  with weekly_rollup as (
    select
      round(coalesce(v_target_vast, 0) * coalesce(v_week_percentage, 25) / 100.0)::int as target_submissions,
      coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
      coalesce(sum(vd.total_acc), 0)::int as total_acc,
      coalesce(sum(vd.total_pending), 0)::int as total_pending,
      coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
      coalesce(sum(vd.total_reject), 0)::int as total_reject,
      coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
      coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
      coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts,
      coalesce(max(vd.promotor_with_input), 0)::int as promotor_with_input
    from public.vast_agg_daily_sator vd
    where vd.sator_id = p_sator_id
      and vd.metric_date between coalesce(v_week_start, v_month_key) and least(coalesce(v_week_end, v_today), v_today)
  )
  select jsonb_build_object(
    'week_start_date', coalesce(v_week_start, v_month_key),
    'week_end_date', least(coalesce(v_week_end, v_today), v_today),
    'target_submissions', wr.target_submissions,
    'total_submissions', wr.total_submissions,
    'total_acc', wr.total_acc,
    'total_pending', wr.total_pending,
    'total_active_pending', wr.total_active_pending,
    'total_reject', wr.total_reject,
    'total_closed_direct', wr.total_closed_direct,
    'total_closed_follow_up', wr.total_closed_follow_up,
    'total_duplicate_alerts', wr.total_duplicate_alerts,
    'promotor_with_input', wr.promotor_with_input,
    'achievement_pct', case
      when wr.target_submissions > 0 then round((wr.total_submissions::numeric / wr.target_submissions::numeric) * 100, 2)
      else 0
    end
  )
  into v_vast_weekly
  from weekly_rollup wr;

  select to_jsonb(vm.*)
  into v_vast_monthly
  from public.vast_agg_monthly_sator vm
  where vm.sator_id = p_sator_id
    and vm.month_key = v_month_key
  limit 1;

  if coalesce(v_vast_monthly, '{}'::jsonb) = '{}'::jsonb then
    with monthly_rollup as (
      select
        round(coalesce(v_target_vast, 0))::int as target_submissions,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts,
        coalesce(max(vd.promotor_with_input), 0)::int as promotor_with_input
      from public.vast_agg_daily_sator vd
      where vd.sator_id = p_sator_id
        and vd.metric_date between v_month_key and v_today
    )
    select jsonb_build_object(
      'month_key', v_month_key,
      'target_submissions', mr.target_submissions,
      'total_submissions', mr.total_submissions,
      'total_acc', mr.total_acc,
      'total_pending', mr.total_pending,
      'total_active_pending', mr.total_active_pending,
      'total_reject', mr.total_reject,
      'total_closed_direct', mr.total_closed_direct,
      'total_closed_follow_up', mr.total_closed_follow_up,
      'total_duplicate_alerts', mr.total_duplicate_alerts,
      'promotor_with_input', mr.promotor_with_input,
      'achievement_pct', case
        when mr.target_submissions > 0 then round((mr.total_submissions::numeric / mr.target_submissions::numeric) * 100, 2)
        else 0
      end
    )
    into v_vast_monthly
    from monthly_rollup mr;
  end if;

  return jsonb_build_object(
    'profile', v_profile,
    'period', coalesce(v_summary -> 'period', '{}'::jsonb),
    'counts', coalesce(v_summary -> 'counts', '{}'::jsonb),
    'daily', coalesce(v_summary -> 'daily', '{}'::jsonb),
    'weekly', coalesce(v_summary -> 'weekly', '{}'::jsonb),
    'monthly', coalesce(v_summary -> 'monthly', '{}'::jsonb),
    'agenda', coalesce(v_summary -> 'agenda', '[]'::jsonb),
    'daily_promotors', coalesce(v_promotor_cards -> 'daily', '[]'::jsonb),
    'weekly_promotors', coalesce(v_promotor_cards -> 'weekly', '[]'::jsonb),
    'monthly_promotors', coalesce(v_promotor_cards -> 'monthly', '[]'::jsonb),
    'focus_products', v_focus_products,
    'vast_daily', coalesce(v_vast_daily, '{}'::jsonb),
    'vast_weekly', coalesce(v_vast_weekly, '{}'::jsonb),
    'vast_monthly', coalesce(v_vast_monthly, '{}'::jsonb)
  );
end;
$function$;

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
  v_month_key date := date_trunc('month', p_date)::date;
  v_month_start date := date_trunc('month', p_date)::date;
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_number integer := 1;
  v_week_start_day integer := 1;
  v_week_end_day integer := 7;
  v_week_start date;
  v_week_end date;
  v_active_week_percentage numeric := 25;
  v_target_vast numeric := 0;
begin
  v_base := coalesce(
    public.get_spv_home_snapshot_base(p_spv_id, p_date),
    '{}'::jsonb
  );

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is not null then
    v_week_number := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);

    select
      coalesce(wt.start_day, ((v_week_number - 1) * 7) + 1),
      coalesce(
        wt.end_day,
        case
          when v_week_number < 4 then v_week_number * 7
          else extract(day from v_period_end)::int
        end
      ),
      coalesce(wt.percentage, 25)
    into v_week_start_day, v_week_end_day, v_active_week_percentage
    from public.weekly_targets wt
    where wt.period_id = v_period_id
      and wt.week_number = v_week_number;

    v_week_start_day := coalesce(v_week_start_day, ((v_week_number - 1) * 7) + 1);
    v_week_end_day := coalesce(
      v_week_end_day,
      case
        when v_week_number < 4 then v_week_number * 7
        else extract(day from v_period_end)::int
      end
    );
    v_active_week_percentage := coalesce(v_active_week_percentage, 25);

    v_week_start := greatest(v_period_start, v_period_start + (v_week_start_day - 1));
    v_week_end := least(v_period_end, v_period_start + (v_week_end_day - 1));

    select coalesce(ut.target_vast, 0)
    into v_target_vast
    from public.user_targets ut
    where ut.user_id = p_spv_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc nulls last
    limit 1;
  else
    v_week_start := v_month_start;
    v_week_end := p_date;
  end if;

  select to_jsonb(vd.*)
  into v_vast_daily
  from public.vast_agg_daily_spv vd
  where vd.spv_id = p_spv_id
    and vd.metric_date = p_date
  limit 1;

  with weekly_rollup as (
    select
      round(coalesce(v_target_vast, 0) * coalesce(v_active_week_percentage, 25) / 100.0)::int as target_submissions,
      coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
      coalesce(sum(vd.total_acc), 0)::int as total_acc,
      coalesce(sum(vd.total_pending), 0)::int as total_pending,
      coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
      coalesce(sum(vd.total_reject), 0)::int as total_reject,
      coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
      coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
      coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts,
      coalesce(max(vd.promotor_with_input), 0)::int as promotor_with_input
    from public.vast_agg_daily_spv vd
    where vd.spv_id = p_spv_id
      and vd.metric_date between coalesce(v_week_start, v_month_start) and least(coalesce(v_week_end, p_date), p_date)
  )
  select jsonb_build_object(
    'week_start_date', coalesce(v_week_start, v_month_start),
    'week_end_date', least(coalesce(v_week_end, p_date), p_date),
    'target_submissions', wr.target_submissions,
    'total_submissions', wr.total_submissions,
    'total_acc', wr.total_acc,
    'total_pending', wr.total_pending,
    'total_active_pending', wr.total_active_pending,
    'total_reject', wr.total_reject,
    'total_closed_direct', wr.total_closed_direct,
    'total_closed_follow_up', wr.total_closed_follow_up,
    'total_duplicate_alerts', wr.total_duplicate_alerts,
    'promotor_with_input', wr.promotor_with_input,
    'achievement_pct', case
      when wr.target_submissions > 0 then round((wr.total_submissions::numeric / wr.target_submissions::numeric) * 100, 2)
      else 0
    end
  )
  into v_vast_weekly
  from weekly_rollup wr;

  select to_jsonb(vm.*)
  into v_vast_monthly
  from public.vast_agg_monthly_spv vm
  where vm.spv_id = p_spv_id
    and vm.month_key = v_month_key
  limit 1;

  if coalesce(v_vast_monthly, '{}'::jsonb) = '{}'::jsonb then
    with monthly_rollup as (
      select
        round(coalesce(v_target_vast, 0))::int as target_submissions,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts,
        coalesce(max(vd.promotor_with_input), 0)::int as promotor_with_input
      from public.vast_agg_daily_spv vd
      where vd.spv_id = p_spv_id
        and vd.metric_date between v_month_start and p_date
    )
    select jsonb_build_object(
      'month_key', v_month_key,
      'target_submissions', mr.target_submissions,
      'total_submissions', mr.total_submissions,
      'total_acc', mr.total_acc,
      'total_pending', mr.total_pending,
      'total_active_pending', mr.total_active_pending,
      'total_reject', mr.total_reject,
      'total_closed_direct', mr.total_closed_direct,
      'total_closed_follow_up', mr.total_closed_follow_up,
      'total_duplicate_alerts', mr.total_duplicate_alerts,
      'promotor_with_input', mr.promotor_with_input,
      'achievement_pct', case
        when mr.target_submissions > 0 then round((mr.total_submissions::numeric / mr.target_submissions::numeric) * 100, 2)
        else 0
      end
    )
    into v_vast_monthly
    from monthly_rollup mr;
  end if;

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
      coalesce(sum(case when o.order_date between coalesce(v_week_start, v_month_start) and p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_weekly,
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

grant execute on function public.get_sator_home_snapshot(uuid) to authenticated;
grant execute on function public.get_spv_home_snapshot(uuid, date) to authenticated;
