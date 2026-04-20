create or replace function public.get_sator_vast_page_snapshot(
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_today date := coalesce(p_date, current_date);
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_number integer := 1;
  v_week_start date := v_today;
  v_week_end date := v_today;
  v_week_percentage numeric := 25;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'sator' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where v_today between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is not null then
    with week_rows as (
      select
        gen.week_number,
        coalesce(wt.start_day, ((gen.week_number - 1) * 7) + 1) as start_day,
        coalesce(
          wt.end_day,
          case
            when gen.week_number < 4 then gen.week_number * 7
            else extract(day from v_period_end)::int
          end
        ) as end_day,
        coalesce(wt.percentage, 25) as percentage
      from generate_series(1, 4) as gen(week_number)
      left join public.weekly_targets wt
        on wt.period_id = v_period_id
       and wt.week_number = gen.week_number
    )
    select
      wr.week_number,
      greatest(v_period_start, (v_period_start + (wr.start_day - 1) * interval '1 day')::date),
      least(v_period_end, (v_period_start + (wr.end_day - 1) * interval '1 day')::date),
      wr.percentage
    into v_week_number, v_week_start, v_week_end, v_week_percentage
    from week_rows wr
    where extract(day from v_today)::int between wr.start_day and wr.end_day
    order by wr.week_number
    limit 1;
  end if;

  return (
    with profile as (
      select
        coalesce(u.full_name, 'SATOR') as full_name,
        coalesce(u.area, '-') as area
      from public.users u
      where u.id = v_actor_id
    ),
    promotor_scope as (
      select distinct
        p.id as promotor_id,
        coalesce(nullif(trim(p.nickname), ''), coalesce(p.full_name, 'Promotor')) as display_name
      from public.hierarchy_sator_promotor hsp
      join public.users p on p.id = hsp.promotor_id
      where hsp.sator_id = v_actor_id
        and hsp.active = true
        and p.deleted_at is null
    ),
    latest_store as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        coalesce(st.store_name, '-') as store_name
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      where aps.active = true
        and aps.promotor_id in (select promotor_id from promotor_scope)
      order by aps.promotor_id, aps.created_at desc nulls last, aps.store_id
    ),
    targets as (
      select
        ps.promotor_id,
        coalesce(ut.target_vast, 0)::int as monthly_target,
        public.get_effective_workday_count(ps.promotor_id, v_today, v_period_end) as remaining_workdays
      from promotor_scope ps
      left join public.user_targets ut
        on ut.user_id = ps.promotor_id
       and ut.period_id = v_period_id
    ),
    agg_before_today as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date between v_period_start and (v_today - 1)
      group by vd.promotor_id
    ),
    agg_daily as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date = v_today
      group by vd.promotor_id
    ),
    agg_weekly as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date between v_week_start and least(v_week_end, v_today)
      group by vd.promotor_id
    ),
    agg_monthly as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date between v_period_start and v_today
      group by vd.promotor_id
    ),
    promotor_targets as (
      select
        t.promotor_id,
        t.monthly_target,
        round(t.monthly_target * v_week_percentage / 100.0, 0)::int as weekly_target,
        case
          when coalesce(t.remaining_workdays, 0) > 0
            then ceil(greatest(t.monthly_target - coalesce(bt.total_submissions, 0), 0)::numeric / t.remaining_workdays::numeric)::int
          else 0
        end as daily_target,
        t.remaining_workdays
      from targets t
      left join agg_before_today bt on bt.promotor_id = t.promotor_id
    ),
    daily_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(pt.daily_target), 0),
        'total_submissions', coalesce(sum(ad.total_submissions), 0),
        'total_acc', coalesce(sum(ad.total_acc), 0),
        'total_pending', coalesce(sum(ad.total_pending), 0),
        'total_active_pending', coalesce(sum(ad.total_active_pending), 0),
        'total_reject', coalesce(sum(ad.total_reject), 0),
        'total_closed_direct', coalesce(sum(ad.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(ad.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(ad.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(ad.total_submissions, 0) > 0),
        'achievement_pct', case when coalesce(sum(pt.daily_target), 0) > 0
          then (coalesce(sum(ad.total_submissions), 0)::numeric / sum(pt.daily_target)::numeric) * 100
          else 0 end,
        'underperform', case when coalesce(sum(pt.daily_target), 0) <= 0
          then false
          else coalesce(sum(ad.total_submissions), 0) < sum(pt.daily_target) end
      ) as data
      from promotor_targets pt
      left join agg_daily ad on ad.promotor_id = pt.promotor_id
    ),
    weekly_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(pt.weekly_target), 0),
        'total_submissions', coalesce(sum(aw.total_submissions), 0),
        'total_acc', coalesce(sum(aw.total_acc), 0),
        'total_pending', coalesce(sum(aw.total_pending), 0),
        'total_active_pending', coalesce(sum(aw.total_active_pending), 0),
        'total_reject', coalesce(sum(aw.total_reject), 0),
        'total_closed_direct', coalesce(sum(aw.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(aw.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(aw.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(aw.total_submissions, 0) > 0),
        'achievement_pct', case when coalesce(sum(pt.weekly_target), 0) > 0
          then (coalesce(sum(aw.total_submissions), 0)::numeric / sum(pt.weekly_target)::numeric) * 100
          else 0 end,
        'underperform', case when coalesce(sum(pt.weekly_target), 0) <= 0
          then false
          else coalesce(sum(aw.total_submissions), 0) < sum(pt.weekly_target) end
      ) as data
      from promotor_targets pt
      left join agg_weekly aw on aw.promotor_id = pt.promotor_id
    ),
    monthly_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(pt.monthly_target), 0),
        'total_submissions', coalesce(sum(am.total_submissions), 0),
        'total_acc', coalesce(sum(am.total_acc), 0),
        'total_pending', coalesce(sum(am.total_pending), 0),
        'total_active_pending', coalesce(sum(am.total_active_pending), 0),
        'total_reject', coalesce(sum(am.total_reject), 0),
        'total_closed_direct', coalesce(sum(am.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(am.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(am.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(am.total_submissions, 0) > 0),
        'achievement_pct', case when coalesce(sum(pt.monthly_target), 0) > 0
          then (coalesce(sum(am.total_submissions), 0)::numeric / sum(pt.monthly_target)::numeric) * 100
          else 0 end,
        'underperform', case when coalesce(sum(pt.monthly_target), 0) <= 0
          then false
          else coalesce(sum(am.total_submissions), 0) < sum(pt.monthly_target) end
      ) as data
      from promotor_targets pt
      left join agg_monthly am on am.promotor_id = pt.promotor_id
    ),
    rows_daily as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(pt.monthly_target, 0),
          'target_vast', coalesce(pt.daily_target, 0),
          'period_submissions', coalesce(ad.total_submissions, 0),
          'pending', coalesce(ad.total_active_pending, 0),
          'duplicate_alerts', coalesce(ad.total_duplicate_alerts, 0),
          'total_acc', coalesce(ad.total_acc, 0),
          'total_reject', coalesce(ad.total_reject, 0),
          'promotor_with_input', case when coalesce(ad.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case when coalesce(pt.daily_target, 0) > 0
            then (coalesce(ad.total_submissions, 0)::numeric / pt.daily_target::numeric) * 100
            else 0 end,
          'underperform', case when coalesce(pt.daily_target, 0) <= 0
            then false
            else coalesce(ad.total_submissions, 0) < pt.daily_target end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join promotor_targets pt on pt.promotor_id = ps.promotor_id
        left join agg_daily ad on ad.promotor_id = ps.promotor_id
      ) q
    ),
    rows_weekly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(pt.monthly_target, 0),
          'target_vast', coalesce(pt.weekly_target, 0),
          'period_submissions', coalesce(aw.total_submissions, 0),
          'pending', coalesce(aw.total_active_pending, 0),
          'duplicate_alerts', coalesce(aw.total_duplicate_alerts, 0),
          'total_acc', coalesce(aw.total_acc, 0),
          'total_reject', coalesce(aw.total_reject, 0),
          'promotor_with_input', case when coalesce(aw.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case when coalesce(pt.weekly_target, 0) > 0
            then (coalesce(aw.total_submissions, 0)::numeric / pt.weekly_target::numeric) * 100
            else 0 end,
          'underperform', case when coalesce(pt.weekly_target, 0) <= 0
            then false
            else coalesce(aw.total_submissions, 0) < pt.weekly_target end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join promotor_targets pt on pt.promotor_id = ps.promotor_id
        left join agg_weekly aw on aw.promotor_id = ps.promotor_id
      ) q
    ),
    rows_monthly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(pt.monthly_target, 0),
          'target_vast', coalesce(pt.monthly_target, 0),
          'period_submissions', coalesce(am.total_submissions, 0),
          'pending', coalesce(am.total_active_pending, 0),
          'duplicate_alerts', coalesce(am.total_duplicate_alerts, 0),
          'total_acc', coalesce(am.total_acc, 0),
          'total_reject', coalesce(am.total_reject, 0),
          'promotor_with_input', case when coalesce(am.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case when coalesce(pt.monthly_target, 0) > 0
            then (coalesce(am.total_submissions, 0)::numeric / pt.monthly_target::numeric) * 100
            else 0 end,
          'underperform', case when coalesce(pt.monthly_target, 0) <= 0
            then false
            else coalesce(am.total_submissions, 0) < pt.monthly_target end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join promotor_targets pt on pt.promotor_id = ps.promotor_id
        left join agg_monthly am on am.promotor_id = ps.promotor_id
      ) q
    ),
    alerts as (
      select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc), '[]'::jsonb) as data
      from (
        select id, signal_id, application_id, title, body, created_at, is_read
        from public.vast_alerts
        where recipient_user_id = v_actor_id
        order by created_at desc
        limit 50
      ) a
    )
    select jsonb_build_object(
      'profile', coalesce((select to_jsonb(profile) from profile), '{}'::jsonb),
      'daily', coalesce((select data from daily_summary), '{}'::jsonb),
      'weekly', coalesce((select data from weekly_summary), '{}'::jsonb),
      'monthly', coalesce((select data from monthly_summary), '{}'::jsonb),
      'rows_daily', coalesce((select data from rows_daily), '[]'::jsonb),
      'rows_weekly', coalesce((select data from rows_weekly), '[]'::jsonb),
      'rows_monthly', coalesce((select data from rows_monthly), '[]'::jsonb),
      'alerts', coalesce((select data from alerts), '[]'::jsonb)
    )
  );
end;
$$;

create or replace function public.get_spv_vast_page_snapshot(
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_today date := coalesce(p_date, current_date);
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_number integer := 1;
  v_week_start date := v_today;
  v_week_end date := v_today;
  v_week_percentage numeric := 25;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'spv' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where v_today between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is not null then
    with week_rows as (
      select
        gen.week_number,
        coalesce(wt.start_day, ((gen.week_number - 1) * 7) + 1) as start_day,
        coalesce(
          wt.end_day,
          case
            when gen.week_number < 4 then gen.week_number * 7
            else extract(day from v_period_end)::int
          end
        ) as end_day,
        coalesce(wt.percentage, 25) as percentage
      from generate_series(1, 4) as gen(week_number)
      left join public.weekly_targets wt
        on wt.period_id = v_period_id
       and wt.week_number = gen.week_number
    )
    select
      wr.week_number,
      greatest(v_period_start, (v_period_start + (wr.start_day - 1) * interval '1 day')::date),
      least(v_period_end, (v_period_start + (wr.end_day - 1) * interval '1 day')::date),
      wr.percentage
    into v_week_number, v_week_start, v_week_end, v_week_percentage
    from week_rows wr
    where extract(day from v_today)::int between wr.start_day and wr.end_day
    order by wr.week_number
    limit 1;
  end if;

  return (
    with profile as (
      select
        coalesce(u.full_name, 'SPV') as full_name,
        coalesce(u.area, '-') as area
      from public.users u
      where u.id = v_actor_id
    ),
    promotor_scope as (
      select distinct
        p.id as promotor_id,
        coalesce(nullif(trim(p.nickname), ''), coalesce(p.full_name, 'Promotor')) as display_name
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
       and hsp.active = true
      join public.users p on p.id = hsp.promotor_id
      where hss.spv_id = v_actor_id
        and hss.active = true
        and p.deleted_at is null
    ),
    latest_store as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        coalesce(st.store_name, '-') as store_name
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      where aps.active = true
        and aps.promotor_id in (select promotor_id from promotor_scope)
      order by aps.promotor_id, aps.created_at desc nulls last, aps.store_id
    ),
    targets as (
      select
        ps.promotor_id,
        coalesce(ut.target_vast, 0)::int as monthly_target,
        public.get_effective_workday_count(ps.promotor_id, v_today, v_period_end) as remaining_workdays
      from promotor_scope ps
      left join public.user_targets ut
        on ut.user_id = ps.promotor_id
       and ut.period_id = v_period_id
    ),
    agg_before_today as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date between v_period_start and (v_today - 1)
      group by vd.promotor_id
    ),
    agg_daily as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date = v_today
      group by vd.promotor_id
    ),
    agg_weekly as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date between v_week_start and least(v_week_end, v_today)
      group by vd.promotor_id
    ),
    agg_monthly as (
      select
        vd.promotor_id,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts
      from public.vast_agg_daily_promotor vd
      where vd.promotor_id in (select promotor_id from promotor_scope)
        and vd.metric_date between v_period_start and v_today
      group by vd.promotor_id
    ),
    promotor_targets as (
      select
        t.promotor_id,
        t.monthly_target,
        round(t.monthly_target * v_week_percentage / 100.0, 0)::int as weekly_target,
        case
          when coalesce(t.remaining_workdays, 0) > 0
            then ceil(greatest(t.monthly_target - coalesce(bt.total_submissions, 0), 0)::numeric / t.remaining_workdays::numeric)::int
          else 0
        end as daily_target
      from targets t
      left join agg_before_today bt on bt.promotor_id = t.promotor_id
    ),
    daily_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(pt.daily_target), 0),
        'total_submissions', coalesce(sum(ad.total_submissions), 0),
        'total_acc', coalesce(sum(ad.total_acc), 0),
        'total_pending', coalesce(sum(ad.total_pending), 0),
        'total_active_pending', coalesce(sum(ad.total_active_pending), 0),
        'total_reject', coalesce(sum(ad.total_reject), 0),
        'total_closed_direct', coalesce(sum(ad.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(ad.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(ad.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(ad.total_submissions, 0) > 0),
        'achievement_pct', case when coalesce(sum(pt.daily_target), 0) > 0
          then (coalesce(sum(ad.total_submissions), 0)::numeric / sum(pt.daily_target)::numeric) * 100
          else 0 end,
        'underperform', case when coalesce(sum(pt.daily_target), 0) <= 0
          then false
          else coalesce(sum(ad.total_submissions), 0) < sum(pt.daily_target) end
      ) as data
      from promotor_targets pt
      left join agg_daily ad on ad.promotor_id = pt.promotor_id
    ),
    weekly_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(pt.weekly_target), 0),
        'total_submissions', coalesce(sum(aw.total_submissions), 0),
        'total_acc', coalesce(sum(aw.total_acc), 0),
        'total_pending', coalesce(sum(aw.total_pending), 0),
        'total_active_pending', coalesce(sum(aw.total_active_pending), 0),
        'total_reject', coalesce(sum(aw.total_reject), 0),
        'total_closed_direct', coalesce(sum(aw.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(aw.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(aw.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(aw.total_submissions, 0) > 0),
        'achievement_pct', case when coalesce(sum(pt.weekly_target), 0) > 0
          then (coalesce(sum(aw.total_submissions), 0)::numeric / sum(pt.weekly_target)::numeric) * 100
          else 0 end,
        'underperform', case when coalesce(sum(pt.weekly_target), 0) <= 0
          then false
          else coalesce(sum(aw.total_submissions), 0) < sum(pt.weekly_target) end
      ) as data
      from promotor_targets pt
      left join agg_weekly aw on aw.promotor_id = pt.promotor_id
    ),
    monthly_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(pt.monthly_target), 0),
        'total_submissions', coalesce(sum(am.total_submissions), 0),
        'total_acc', coalesce(sum(am.total_acc), 0),
        'total_pending', coalesce(sum(am.total_pending), 0),
        'total_active_pending', coalesce(sum(am.total_active_pending), 0),
        'total_reject', coalesce(sum(am.total_reject), 0),
        'total_closed_direct', coalesce(sum(am.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(am.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(am.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(am.total_submissions, 0) > 0),
        'achievement_pct', case when coalesce(sum(pt.monthly_target), 0) > 0
          then (coalesce(sum(am.total_submissions), 0)::numeric / sum(pt.monthly_target)::numeric) * 100
          else 0 end,
        'underperform', case when coalesce(sum(pt.monthly_target), 0) <= 0
          then false
          else coalesce(sum(am.total_submissions), 0) < sum(pt.monthly_target) end
      ) as data
      from promotor_targets pt
      left join agg_monthly am on am.promotor_id = pt.promotor_id
    ),
    rows_daily as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(pt.monthly_target, 0),
          'period_submissions', coalesce(ad.total_submissions, 0),
          'target', coalesce(pt.daily_target, 0),
          'pending', coalesce(ad.total_active_pending, 0),
          'duplicates', coalesce(ad.total_duplicate_alerts, 0),
          'total_acc', coalesce(ad.total_acc, 0),
          'total_reject', coalesce(ad.total_reject, 0),
          'achievement_pct', case when coalesce(pt.daily_target, 0) > 0
            then (coalesce(ad.total_submissions, 0)::numeric / pt.daily_target::numeric) * 100
            else 0 end,
          'underperform', case when coalesce(pt.daily_target, 0) <= 0
            then false
            else coalesce(ad.total_submissions, 0) < pt.daily_target end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join promotor_targets pt on pt.promotor_id = ps.promotor_id
        left join agg_daily ad on ad.promotor_id = ps.promotor_id
      ) q
    ),
    rows_weekly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(pt.monthly_target, 0),
          'period_submissions', coalesce(aw.total_submissions, 0),
          'target', coalesce(pt.weekly_target, 0),
          'pending', coalesce(aw.total_active_pending, 0),
          'duplicates', coalesce(aw.total_duplicate_alerts, 0),
          'total_acc', coalesce(aw.total_acc, 0),
          'total_reject', coalesce(aw.total_reject, 0),
          'achievement_pct', case when coalesce(pt.weekly_target, 0) > 0
            then (coalesce(aw.total_submissions, 0)::numeric / pt.weekly_target::numeric) * 100
            else 0 end,
          'underperform', case when coalesce(pt.weekly_target, 0) <= 0
            then false
            else coalesce(aw.total_submissions, 0) < pt.weekly_target end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join promotor_targets pt on pt.promotor_id = ps.promotor_id
        left join agg_weekly aw on aw.promotor_id = ps.promotor_id
      ) q
    ),
    rows_monthly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(pt.monthly_target, 0),
          'period_submissions', coalesce(am.total_submissions, 0),
          'target', coalesce(pt.monthly_target, 0),
          'pending', coalesce(am.total_active_pending, 0),
          'duplicates', coalesce(am.total_duplicate_alerts, 0),
          'total_acc', coalesce(am.total_acc, 0),
          'total_reject', coalesce(am.total_reject, 0),
          'achievement_pct', case when coalesce(pt.monthly_target, 0) > 0
            then (coalesce(am.total_submissions, 0)::numeric / pt.monthly_target::numeric) * 100
            else 0 end,
          'underperform', case when coalesce(pt.monthly_target, 0) <= 0
            then false
            else coalesce(am.total_submissions, 0) < pt.monthly_target end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join promotor_targets pt on pt.promotor_id = ps.promotor_id
        left join agg_monthly am on am.promotor_id = ps.promotor_id
      ) q
    ),
    alerts as (
      select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc), '[]'::jsonb) as data
      from (
        select id, signal_id, application_id, title, body, created_at, is_read
        from public.vast_alerts
        where recipient_user_id = v_actor_id
        order by created_at desc
        limit 50
      ) a
    )
    select jsonb_build_object(
      'profile', coalesce((select to_jsonb(profile) from profile), '{}'::jsonb),
      'daily', coalesce((select data from daily_summary), '{}'::jsonb),
      'weekly', coalesce((select data from weekly_summary), '{}'::jsonb),
      'monthly', coalesce((select data from monthly_summary), '{}'::jsonb),
      'rows_daily', coalesce((select data from rows_daily), '[]'::jsonb),
      'rows_weekly', coalesce((select data from rows_weekly), '[]'::jsonb),
      'rows_monthly', coalesce((select data from rows_monthly), '[]'::jsonb),
      'alerts', coalesce((select data from alerts), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_sator_vast_page_snapshot(date) to authenticated;
grant execute on function public.get_spv_vast_page_snapshot(date) to authenticated;
