create or replace function public.get_vast_promotor_closing_omzet(
  p_promotor_id uuid,
  p_start_date date,
  p_end_date date
)
returns numeric
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(sum(coalesce(pv.srp, 0)), 0)::numeric
  from public.vast_applications a
  left join public.vast_closings vc on vc.application_id = a.id
  left join public.product_variants pv on pv.id = a.product_variant_id
  where a.promotor_id = p_promotor_id
    and a.deleted_at is null
    and a.lifecycle_status in ('closed_direct', 'closed_follow_up')
    and coalesce(vc.closing_date, a.application_date)
      between p_start_date and p_end_date;
$$;

grant execute on function public.get_vast_promotor_closing_omzet(uuid, date, date)
to authenticated;

create or replace function public.get_promotor_vast_page_snapshot(
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
  v_month_start date := date_trunc('month', coalesce(p_date, current_date))::date;
  v_month_end date := (date_trunc('month', coalesce(p_date, current_date)) + interval '1 month - 1 day')::date;
  v_week_start date := coalesce(p_date, current_date);
  v_week_end date := coalesce(p_date, current_date);
  v_current_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_number integer := 1;
  v_week_percentage integer := 25;
  v_week_day_count integer := 7;
  v_week_start_day integer := 1;
  v_week_end_day integer := 7;
  v_monthly_target integer := 0;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'promotor' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  v_current_period_id := public.get_current_target_period();

  select tp.start_date, tp.end_date
  into v_period_start, v_period_end
  from public.target_periods tp
  where tp.id = v_current_period_id;

  if v_period_start is not null then
    select
      w.week_number,
      coalesce(w.percentage, 25),
      coalesce(w.start_day, 1),
      coalesce(w.end_day, coalesce(w.start_day, 1)),
      greatest(coalesce(w.end_day, w.start_day) - coalesce(w.start_day, 1) + 1, 1)
    into
      v_week_number,
      v_week_percentage,
      v_week_start_day,
      v_week_end_day,
      v_week_day_count
    from (
      select
        wt.week_number,
        wt.start_day,
        wt.end_day,
        wt.percentage,
        row_number() over (
          partition by wt.week_number
          order by case when wt.period_id = v_current_period_id then 0 else 1 end, wt.week_number
        ) as rn
      from public.weekly_targets wt
      where coalesce(wt.period_id, v_current_period_id) = v_current_period_id
    ) w
    where w.rn = 1
      and v_today between
        (v_period_start + (w.start_day - 1) * interval '1 day')::date
        and
        (v_period_start + (w.end_day - 1) * interval '1 day')::date
    order by w.week_number
    limit 1;

    v_week_start := greatest(
      v_period_start,
      (v_period_start + (v_week_start_day - 1) * interval '1 day')::date
    );
    v_week_end := least(
      coalesce(v_period_end, v_week_end),
      (v_period_start + (v_week_end_day - 1) * interval '1 day')::date
    );
  end if;

  select coalesce(ut.target_vast, 0)::int
  into v_monthly_target
  from public.user_targets ut
  where ut.user_id = v_actor_id
    and ut.period_id = v_current_period_id
  limit 1;

  return (
    with profile as (
      select
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'Promotor')) as name
      from public.users u
      where u.id = v_actor_id
    ),
    store_row as (
      select jsonb_build_object(
        'store_id', aps.store_id,
        'stores', jsonb_build_object(
          'store_name', coalesce(st.store_name, ''),
          'area', coalesce(st.area, '')
        )
      ) as data
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      where aps.promotor_id = v_actor_id
        and aps.active = true
      order by aps.created_at desc nulls last
      limit 1
    ),
    products as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'model_name', p.model_name
          )
          order by p.model_name
        ),
        '[]'::jsonb
      ) as data
      from public.products p
      where coalesce(trim(p.model_name), '') <> ''
    ),
    monthly_summary as (
      select coalesce(to_jsonb(m), '{}'::jsonb) as data
      from public.vast_agg_monthly_promotor m
      where m.promotor_id = v_actor_id
        and m.month_key = v_month_start
      limit 1
    ),
    daily_stats as (
      select jsonb_build_object(
        'start', v_today,
        'end', v_today,
        'target', case
          when v_monthly_target <= 0 then 0
          else ceil(round(v_monthly_target::numeric * v_week_percentage::numeric / 100.0, 0) / v_week_day_count::numeric)::int
        end,
        'submissions', count(*)::int,
        'acc', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'acc'
             or lower(coalesce(a.lifecycle_status, '')) in ('closed_direct', 'closed_follow_up')
        )::int,
        'pending', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'pending'
             or lower(coalesce(a.lifecycle_status, '')) = 'approved_pending'
        )::int,
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int,
        'closing_omzet', public.get_vast_promotor_closing_omzet(v_actor_id, v_today, v_today)
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date = v_today
    ),
    weekly_target as (
      select round(v_monthly_target::numeric * v_week_percentage::numeric / 100.0, 0)::int as target
    ),
    weekly_stats as (
      select jsonb_build_object(
        'start', v_week_start,
        'end', v_week_end,
        'target', coalesce((select target from weekly_target), 0),
        'submissions', count(*)::int,
        'acc', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'acc'
             or lower(coalesce(a.lifecycle_status, '')) in ('closed_direct', 'closed_follow_up')
        )::int,
        'pending', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'pending'
             or lower(coalesce(a.lifecycle_status, '')) = 'approved_pending'
        )::int,
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int,
        'closing_omzet', public.get_vast_promotor_closing_omzet(v_actor_id, v_week_start, v_week_end)
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date between v_week_start and v_week_end
    ),
    monthly_stats as (
      select jsonb_build_object(
        'start', v_month_start,
        'end', v_month_end,
        'target', v_monthly_target,
        'submissions', count(*)::int,
        'acc', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'acc'
             or lower(coalesce(a.lifecycle_status, '')) in ('closed_direct', 'closed_follow_up')
        )::int,
        'pending', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'pending'
             or lower(coalesce(a.lifecycle_status, '')) = 'approved_pending'
        )::int,
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int,
        'closing_omzet', public.get_vast_promotor_closing_omzet(v_actor_id, v_month_start, v_month_end)
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date between v_month_start and v_month_end
    ),
    weeks as (
      select
        w.week_number,
        w.start_day,
        w.end_day,
        coalesce(w.percentage, 0) as percentage
      from (
        select
          wt.week_number,
          wt.start_day,
          wt.end_day,
          wt.percentage,
          row_number() over (
            partition by wt.week_number
            order by case when wt.period_id = v_current_period_id then 0 else 1 end, wt.week_number
          ) as rn
        from public.weekly_targets wt
        where coalesce(wt.period_id, v_current_period_id) = v_current_period_id
      ) w
      where w.rn = 1
      order by w.week_number
    ),
    weekly_breakdown as (
      select coalesce(jsonb_agg(row_data order by week_number), '[]'::jsonb) as data
      from (
        select
          wk.week_number,
          jsonb_build_object(
            'label', 'Week ' || wk.week_number,
            'target', round(v_monthly_target::numeric * wk.percentage::numeric / 100.0, 0)::int,
            'submissions', coalesce(count(ar.*), 0)::int,
            'acc', coalesce(count(*) filter (where ar.outcome_status = 'acc' or ar.lifecycle_status in ('closed_direct', 'closed_follow_up')), 0)::int,
            'pending', coalesce(count(*) filter (where ar.outcome_status = 'pending' or ar.lifecycle_status = 'approved_pending'), 0)::int,
            'reject', coalesce(count(*) filter (where ar.outcome_status = 'reject' or ar.lifecycle_status = 'rejected'), 0)::int,
            'closing_omzet', public.get_vast_promotor_closing_omzet(
              v_actor_id,
              greatest(v_period_start, (v_period_start + (wk.start_day - 1) * interval '1 day')::date),
              least(v_period_end, (v_period_start + (wk.end_day - 1) * interval '1 day')::date)
            )
          ) as row_data
        from weeks wk
        left join lateral (
          select
            lower(coalesce(a.outcome_status, '')) as outcome_status,
            lower(coalesce(a.lifecycle_status, '')) as lifecycle_status
          from public.vast_applications a
          where a.promotor_id = v_actor_id
            and a.deleted_at is null
            and a.application_date between v_month_start and v_month_end
            and extract(day from a.application_date)::int between wk.start_day and wk.end_day
        ) ar on true
        group by wk.week_number, wk.percentage, wk.start_day, wk.end_day
      ) q
    ),
    pending_items as (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.application_date desc), '[]'::jsonb) as data
      from (
        select
          id, customer_name, customer_phone, product_label, limit_amount,
          dp_amount, tenor_months, application_date, notes
        from public.vast_applications
        where promotor_id = v_actor_id
          and lifecycle_status = 'approved_pending'
          and deleted_at is null
        order by application_date desc
      ) x
    ),
    history_items as (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) as data
      from (
        select
          id, customer_name, customer_phone, pekerjaan, monthly_income,
          product_label, outcome_status, lifecycle_status,
          application_date, created_at,
          limit_amount, dp_amount, tenor_months, notes
        from public.vast_applications
        where promotor_id = v_actor_id
          and deleted_at is null
        order by created_at desc
        limit 100
      ) x
    ),
    reminders as (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.scheduled_date), '[]'::jsonb) as data
      from (
        select
          id, reminder_type, scheduled_date, reminder_title, reminder_body, status
        from public.vast_reminders
        where promotor_id = v_actor_id
        order by scheduled_date
      ) x
    )
    select jsonb_build_object(
      'profile', coalesce((select to_jsonb(profile) from profile), '{}'::jsonb),
      'store', coalesce((select data from store_row), '{}'::jsonb),
      'products', coalesce((select data from products), '[]'::jsonb),
      'monthly_target_vast', v_monthly_target,
      'monthly_summary', coalesce((select data from monthly_summary), '{}'::jsonb),
      'daily_period_stats', coalesce((select data from daily_stats), '{}'::jsonb),
      'weekly_period_stats', coalesce((select data from weekly_stats), '{}'::jsonb),
      'monthly_period_stats', coalesce((select data from monthly_stats), '{}'::jsonb),
      'weekly_breakdown', coalesce((select data from weekly_breakdown), '[]'::jsonb),
      'pending_items', coalesce((select data from pending_items), '[]'::jsonb),
      'history_items', coalesce((select data from history_items), '[]'::jsonb),
      'reminders', coalesce((select data from reminders), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_promotor_vast_page_snapshot(date) to authenticated;

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
      greatest(v_period_start, (wr.start_day - 1) * interval '1 day' + v_period_start),
      least(v_period_end, (wr.end_day - 1) * interval '1 day' + v_period_start),
      wr.percentage
    into v_week_start, v_week_end, v_week_percentage
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
        'closing_omzet', coalesce(sum(public.get_vast_promotor_closing_omzet(pt.promotor_id, v_today, v_today)), 0),
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
        'closing_omzet', coalesce(sum(public.get_vast_promotor_closing_omzet(pt.promotor_id, v_week_start, v_week_end)), 0),
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
        'closing_omzet', coalesce(sum(public.get_vast_promotor_closing_omzet(pt.promotor_id, v_period_start, v_today)), 0),
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
          'closing_omzet', public.get_vast_promotor_closing_omzet(ps.promotor_id, v_today, v_today),
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
          'closing_omzet', public.get_vast_promotor_closing_omzet(ps.promotor_id, v_week_start, v_week_end),
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
          'closing_omzet', public.get_vast_promotor_closing_omzet(ps.promotor_id, v_period_start, v_today),
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
      greatest(v_period_start, (wr.start_day - 1) * interval '1 day' + v_period_start),
      least(v_period_end, (wr.end_day - 1) * interval '1 day' + v_period_start),
      wr.percentage
    into v_week_start, v_week_end, v_week_percentage
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
        'closing_omzet', coalesce(sum(public.get_vast_promotor_closing_omzet(pt.promotor_id, v_today, v_today)), 0),
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
        'closing_omzet', coalesce(sum(public.get_vast_promotor_closing_omzet(pt.promotor_id, v_week_start, v_week_end)), 0),
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
        'closing_omzet', coalesce(sum(public.get_vast_promotor_closing_omzet(pt.promotor_id, v_period_start, v_today)), 0),
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
          'closing_omzet', public.get_vast_promotor_closing_omzet(ps.promotor_id, v_today, v_today),
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
          'closing_omzet', public.get_vast_promotor_closing_omzet(ps.promotor_id, v_week_start, v_week_end),
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
          'closing_omzet', public.get_vast_promotor_closing_omzet(ps.promotor_id, v_period_start, v_today),
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
