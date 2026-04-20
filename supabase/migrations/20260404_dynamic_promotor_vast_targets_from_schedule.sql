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
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_start date := v_today;
  v_week_end date := v_today;
  v_week_number integer := 1;
  v_week_percentage numeric := 25;
  v_monthly_target integer := 0;
  v_daily_target integer := 0;
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

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where v_today between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is null then
    v_period_start := date_trunc('month', v_today)::date;
    v_period_end := (date_trunc('month', v_today) + interval '1 month - 1 day')::date;
  else
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

  select coalesce(ut.target_vast, 0)::int
  into v_monthly_target
  from public.user_targets ut
  where ut.user_id = v_actor_id
    and ut.period_id = v_period_id
  limit 1;

  with submissions_before_today as (
    select coalesce(count(*), 0)::int as total_submissions
    from public.vast_applications a
    where a.promotor_id = v_actor_id
      and a.deleted_at is null
      and a.application_date between v_period_start and (v_today - 1)
  )
  select
    case
      when public.get_effective_workday_count(v_actor_id, v_today, v_period_end) > 0 then
        ceil(
          greatest(
            v_monthly_target - coalesce((select total_submissions from submissions_before_today), 0),
            0
          )::numeric /
          public.get_effective_workday_count(v_actor_id, v_today, v_period_end)::numeric
        )::int
      else 0
    end
  into v_daily_target;

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
        and m.month_key = date_trunc('month', v_period_start)::date
      limit 1
    ),
    daily_stats as (
      select jsonb_build_object(
        'start', v_today,
        'end', v_today,
        'target', v_daily_target,
        'submissions', count(*)::int,
        'acc', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'acc'
             or lower(coalesce(a.lifecycle_status, '')) in ('closed_direct', 'closed_follow_up')
        )::int,
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date = v_today
    ),
    weekly_stats as (
      select jsonb_build_object(
        'start', v_week_start,
        'end', v_week_end,
        'target', round(v_monthly_target * v_week_percentage / 100.0, 0)::int,
        'submissions', count(*)::int,
        'acc', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'acc'
             or lower(coalesce(a.lifecycle_status, '')) in ('closed_direct', 'closed_follow_up')
        )::int,
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date between v_week_start and least(v_week_end, v_today)
    ),
    monthly_stats as (
      select jsonb_build_object(
        'start', v_period_start,
        'end', v_period_end,
        'target', v_monthly_target,
        'submissions', count(*)::int,
        'acc', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'acc'
             or lower(coalesce(a.lifecycle_status, '')) in ('closed_direct', 'closed_follow_up')
        )::int,
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date between v_period_start and v_today
    ),
    weeks as (
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
      order by gen.week_number
    ),
    weekly_breakdown as (
      select coalesce(jsonb_agg(row_data order by week_number), '[]'::jsonb) as data
      from (
        select
          wk.week_number,
          jsonb_build_object(
            'label', 'Week ' || wk.week_number,
            'target', round(v_monthly_target * wk.percentage / 100.0, 0)::int,
            'submissions', count(ar.*)::int,
            'acc', count(*) filter (
              where ar.outcome_status = 'acc'
                 or ar.lifecycle_status in ('closed_direct', 'closed_follow_up')
            )::int,
            'reject', count(*) filter (
              where ar.outcome_status = 'reject'
                 or ar.lifecycle_status = 'rejected'
            )::int
          ) as row_data
        from weeks wk
        left join lateral (
          select
            lower(coalesce(a.outcome_status, '')) as outcome_status,
            lower(coalesce(a.lifecycle_status, '')) as lifecycle_status
          from public.vast_applications a
          where a.promotor_id = v_actor_id
            and a.deleted_at is null
            and a.application_date between v_period_start and v_period_end
            and extract(day from a.application_date)::int between wk.start_day and wk.end_day
        ) ar on true
        group by wk.week_number, wk.percentage
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
