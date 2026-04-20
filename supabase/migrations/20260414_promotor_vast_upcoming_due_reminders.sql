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
      select coalesce(
        jsonb_agg(to_jsonb(x) order by x.days_until_due, x.scheduled_date, x.customer_name),
        '[]'::jsonb
      ) as data
      from (
        select
          vr.id,
          vr.application_id,
          vr.reminder_type,
          vr.scheduled_date,
          vr.reminder_title,
          vr.reminder_body,
          vr.status,
          va.customer_name,
          va.customer_phone,
          va.product_label,
          greatest((vr.scheduled_date - v_today), 0) as days_until_due
        from public.vast_reminders vr
        join public.vast_applications va on va.id = vr.application_id
        where vr.promotor_id = v_actor_id
          and coalesce(vr.status, 'pending') <> 'done'
          and vr.scheduled_date between v_today and (v_today + 3)
        order by vr.scheduled_date, va.customer_name
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
