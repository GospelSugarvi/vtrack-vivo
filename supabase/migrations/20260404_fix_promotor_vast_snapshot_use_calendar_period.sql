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
  v_week_start date := (coalesce(p_date, current_date) - ((extract(isodow from coalesce(p_date, current_date))::int) - 1) * interval '1 day')::date;
  v_week_end date := ((coalesce(p_date, current_date) - ((extract(isodow from coalesce(p_date, current_date))::int) - 1) * interval '1 day')::date + interval '6 day')::date;
  v_current_period_id uuid;
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
          else ceil(v_monthly_target::numeric / extract(day from v_month_end)::numeric)::int
        end,
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
    weekly_target as (
      select (
        (v_monthly_target / 4) +
        case when ((extract(day from v_today)::int - 1) / 7) < (v_monthly_target % 4) then 1 else 0 end
      )::int as target
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
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int
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
        'reject', count(*) filter (
          where lower(coalesce(a.outcome_status, '')) = 'reject'
             or lower(coalesce(a.lifecycle_status, '')) = 'rejected'
        )::int
      ) as data
      from public.vast_applications a
      where a.promotor_id = v_actor_id
        and a.deleted_at is null
        and a.application_date between v_month_start and v_month_end
    ),
    weekly_breakdown as (
      select coalesce(jsonb_agg(row_data order by week_index), '[]'::jsonb) as data
      from (
        with weekly_targets as (
          select
            gs.week_index,
            ('Week ' || (gs.week_index + 1))::text as label,
            ((v_monthly_target / 4) + case when gs.week_index < (v_monthly_target % 4) then 1 else 0 end)::int as target
          from generate_series(0, 3) as gs(week_index)
        ),
        app_rows as (
          select
            case
              when extract(day from a.application_date)::int <= 7 then 0
              when extract(day from a.application_date)::int <= 14 then 1
              when extract(day from a.application_date)::int <= 21 then 2
              else 3
            end as week_index,
            lower(coalesce(a.outcome_status, '')) as outcome_status,
            lower(coalesce(a.lifecycle_status, '')) as lifecycle_status
          from public.vast_applications a
          where a.promotor_id = v_actor_id
            and a.deleted_at is null
            and a.application_date between v_month_start and v_month_end
        )
        select
          wt.week_index,
          jsonb_build_object(
            'label', wt.label,
            'target', wt.target,
            'submissions', coalesce(count(ar.*), 0)::int,
            'acc', coalesce(count(*) filter (where ar.outcome_status = 'acc' or ar.lifecycle_status in ('closed_direct', 'closed_follow_up')), 0)::int,
            'reject', coalesce(count(*) filter (where ar.outcome_status = 'reject' or ar.lifecycle_status = 'rejected'), 0)::int
          ) as row_data
        from weekly_targets wt
        left join app_rows ar on ar.week_index = wt.week_index
        group by wt.week_index, wt.label, wt.target
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
