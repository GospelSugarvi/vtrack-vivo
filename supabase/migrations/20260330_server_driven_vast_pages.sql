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
  v_month_key date := date_trunc('month', coalesce(p_date, current_date))::date;
  v_week_start date := (coalesce(p_date, current_date) - ((extract(isodow from coalesce(p_date, current_date))::int) - 1) * interval '1 day')::date;
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

  return (
    with profile as (
      select
        coalesce(u.full_name, 'SPV') as full_name,
        coalesce(u.area, '-') as area
      from public.users u
      where u.id = v_actor_id
    ),
    active_period as (
      select tp.id
      from public.target_periods tp
      where tp.status = 'active'
        and tp.deleted_at is null
      order by tp.target_year desc, tp.target_month desc, tp.created_at desc
      limit 1
    ),
    promotor_scope as (
      select distinct
        p.id as promotor_id,
        coalesce(nullif(trim(p.nickname), ''), coalesce(p.full_name, 'Promotor')) as display_name,
        coalesce(p.full_name, 'Promotor') as full_name
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
       and hsp.active = true
      join public.users p
        on p.id = hsp.promotor_id
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
        ut.user_id as promotor_id,
        coalesce(ut.target_vast, 0)::int as monthly_target
      from public.user_targets ut
      join active_period ap on ap.id = ut.period_id
      where ut.user_id in (select promotor_id from promotor_scope)
    ),
    daily as (
      select *
      from public.vast_agg_daily_promotor
      where spv_id = v_actor_id
        and metric_date = v_today
        and promotor_id in (select promotor_id from promotor_scope)
    ),
    weekly as (
      select *
      from public.vast_agg_weekly_promotor
      where spv_id = v_actor_id
        and week_start_date = v_week_start
        and promotor_id in (select promotor_id from promotor_scope)
    ),
    monthly as (
      select *
      from public.vast_agg_monthly_promotor
      where spv_id = v_actor_id
        and month_key = v_month_key
        and promotor_id in (select promotor_id from promotor_scope)
    ),
    rows_daily as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'period_submissions', coalesce(d.total_submissions, 0),
          'target', case
            when coalesce(t.monthly_target, 0) <= 0 then 0
            else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
          end,
          'pending', coalesce(d.total_active_pending, 0),
          'duplicates', coalesce(d.total_duplicate_alerts, 0),
          'total_acc', coalesce(d.total_acc, 0),
          'total_reject', coalesce(d.total_reject, 0),
          'achievement_pct', case
            when coalesce(t.monthly_target, 0) > 0
            then (coalesce(d.total_submissions, 0)::numeric / ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)) * 100
            else coalesce(d.achievement_pct, 0)
          end,
          'underperform', case
            when coalesce(t.monthly_target, 0) <= 0 then false
            else coalesce(d.total_submissions, 0) < ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)
          end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join daily d on d.promotor_id = ps.promotor_id
      ) q
    ),
    rows_weekly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'period_submissions', coalesce(w.total_submissions, 0),
          'target',
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int,
          'pending', coalesce(w.total_active_pending, 0),
          'duplicates', coalesce(w.total_duplicate_alerts, 0),
          'total_acc', coalesce(w.total_acc, 0),
          'total_reject', coalesce(w.total_reject, 0),
          'achievement_pct', case
            when coalesce(t.monthly_target, 0) > 0
            then (
              coalesce(w.total_submissions, 0)::numeric /
              greatest(
                (
                  (coalesce(t.monthly_target, 0) / 4) +
                  case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
                )::numeric,
                1
              )
            ) * 100
            else coalesce(w.achievement_pct, 0)
          end,
          'underperform', case
            when coalesce(t.monthly_target, 0) <= 0 then false
            else coalesce(w.total_submissions, 0) <
              (
                (coalesce(t.monthly_target, 0) / 4) +
                case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
              )::int
          end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join weekly w on w.promotor_id = ps.promotor_id
      ) q
    ),
    rows_monthly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'period_submissions', coalesce(m.total_submissions, 0),
          'target', coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0),
          'pending', coalesce(m.total_active_pending, 0),
          'duplicates', coalesce(m.total_duplicate_alerts, 0),
          'total_acc', coalesce(m.total_acc, 0),
          'total_reject', coalesce(m.total_reject, 0),
          'achievement_pct', case
            when coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0) > 0
            then (coalesce(m.total_submissions, 0)::numeric / coalesce(nullif(m.target_submissions, 0), t.monthly_target)::numeric) * 100
            else coalesce(m.achievement_pct, 0)
          end,
          'underperform', coalesce(m.underperform, coalesce(m.total_submissions, 0) < coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0))
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join monthly m on m.promotor_id = ps.promotor_id
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
      'daily', coalesce((select to_jsonb(d) from public.vast_agg_daily_spv d where d.spv_id = v_actor_id and d.metric_date = v_today limit 1), '{}'::jsonb),
      'weekly', coalesce((select to_jsonb(w) from public.vast_agg_weekly_spv w where w.spv_id = v_actor_id and w.week_start_date = v_week_start limit 1), '{}'::jsonb),
      'monthly', coalesce((select to_jsonb(m) from public.vast_agg_monthly_spv m where m.spv_id = v_actor_id and m.month_key = v_month_key limit 1), '{}'::jsonb),
      'rows_daily', coalesce((select data from rows_daily), '[]'::jsonb),
      'rows_weekly', coalesce((select data from rows_weekly), '[]'::jsonb),
      'rows_monthly', coalesce((select data from rows_monthly), '[]'::jsonb),
      'alerts', coalesce((select data from alerts), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_spv_vast_page_snapshot(date) to authenticated;

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
  v_month_key date := date_trunc('month', coalesce(p_date, current_date))::date;
  v_week_start date := (coalesce(p_date, current_date) - ((extract(isodow from coalesce(p_date, current_date))::int) - 1) * interval '1 day')::date;
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

  return (
    with profile as (
      select
        coalesce(u.full_name, 'SATOR') as full_name,
        coalesce(u.area, '-') as area
      from public.users u
      where u.id = v_actor_id
    ),
    active_period as (
      select tp.id
      from public.target_periods tp
      where tp.status = 'active'
        and tp.deleted_at is null
      order by tp.target_year desc, tp.target_month desc, tp.created_at desc
      limit 1
    ),
    promotor_scope as (
      select distinct
        p.id as promotor_id,
        coalesce(nullif(trim(p.nickname), ''), coalesce(p.full_name, 'Promotor')) as display_name,
        coalesce(p.full_name, 'Promotor') as full_name
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
        ut.user_id as promotor_id,
        coalesce(ut.target_vast, 0)::int as monthly_target
      from public.user_targets ut
      join active_period ap on ap.id = ut.period_id
      where ut.user_id in (select promotor_id from promotor_scope)
    ),
    daily as (
      select *
      from public.vast_agg_daily_promotor
      where promotor_id in (select promotor_id from promotor_scope)
        and metric_date = v_today
    ),
    weekly as (
      select *
      from public.vast_agg_weekly_promotor
      where promotor_id in (select promotor_id from promotor_scope)
        and week_start_date = v_week_start
    ),
    monthly as (
      select *
      from public.vast_agg_monthly_promotor
      where promotor_id in (select promotor_id from promotor_scope)
        and month_key = v_month_key
    ),
    rows_daily as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'target_vast', case
            when coalesce(t.monthly_target, 0) <= 0 then 0
            else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
          end,
          'period_submissions', coalesce(d.total_submissions, 0),
          'pending', coalesce(d.total_active_pending, 0),
          'duplicate_alerts', coalesce(d.total_duplicate_alerts, 0),
          'total_acc', coalesce(d.total_acc, 0),
          'total_reject', coalesce(d.total_reject, 0),
          'promotor_with_input', case when coalesce(d.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case
            when coalesce(t.monthly_target, 0) > 0
            then (coalesce(d.total_submissions, 0)::numeric / ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)) * 100
            else coalesce(d.achievement_pct, 0)
          end,
          'underperform', case
            when coalesce(t.monthly_target, 0) <= 0 then false
            else coalesce(d.total_submissions, 0) < ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)
          end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join daily d on d.promotor_id = ps.promotor_id
      ) q
    ),
    rows_weekly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'target_vast',
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int,
          'period_submissions', coalesce(w.total_submissions, 0),
          'pending', coalesce(w.total_active_pending, 0),
          'duplicate_alerts', coalesce(w.total_duplicate_alerts, 0),
          'total_acc', coalesce(w.total_acc, 0),
          'total_reject', coalesce(w.total_reject, 0),
          'promotor_with_input', case when coalesce(w.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case
            when coalesce(t.monthly_target, 0) > 0
            then (
              coalesce(w.total_submissions, 0)::numeric /
              greatest(
                (
                  (coalesce(t.monthly_target, 0) / 4) +
                  case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
                )::numeric,
                1
              )
            ) * 100
            else coalesce(w.achievement_pct, 0)
          end,
          'underperform', case
            when coalesce(t.monthly_target, 0) <= 0 then false
            else coalesce(w.total_submissions, 0) <
              (
                (coalesce(t.monthly_target, 0) / 4) +
                case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
              )::int
          end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join weekly w on w.promotor_id = ps.promotor_id
      ) q
    ),
    rows_monthly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'target_vast', coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0),
          'period_submissions', coalesce(m.total_submissions, 0),
          'pending', coalesce(m.total_active_pending, 0),
          'duplicate_alerts', coalesce(m.total_duplicate_alerts, 0),
          'total_acc', coalesce(m.total_acc, 0),
          'total_reject', coalesce(m.total_reject, 0),
          'promotor_with_input', case when coalesce(m.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case
            when coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0) > 0
            then (coalesce(m.total_submissions, 0)::numeric / coalesce(nullif(m.target_submissions, 0), t.monthly_target)::numeric) * 100
            else coalesce(m.achievement_pct, 0)
          end,
          'underperform', coalesce(m.underperform, coalesce(m.total_submissions, 0) < coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0))
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join monthly m on m.promotor_id = ps.promotor_id
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
      'daily', coalesce((select to_jsonb(d) from public.vast_agg_daily_sator d where d.sator_id = v_actor_id and d.metric_date = v_today limit 1), '{}'::jsonb),
      'weekly', coalesce((select to_jsonb(w) from public.vast_agg_weekly_sator w where w.sator_id = v_actor_id and w.week_start_date = v_week_start limit 1), '{}'::jsonb),
      'monthly', coalesce((select to_jsonb(m) from public.vast_agg_monthly_sator m where m.sator_id = v_actor_id and m.month_key = v_month_key limit 1), '{}'::jsonb),
      'rows_daily', coalesce((select data from rows_daily), '[]'::jsonb),
      'rows_weekly', coalesce((select data from rows_weekly), '[]'::jsonb),
      'rows_monthly', coalesce((select data from rows_monthly), '[]'::jsonb),
      'alerts', coalesce((select data from alerts), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_sator_vast_page_snapshot(date) to authenticated;

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

  select coalesce(ut.target_vast, 0)::int
  into v_monthly_target
  from public.user_targets ut
  join public.target_periods tp on tp.id = ut.period_id
  where ut.user_id = v_actor_id
    and tp.status = 'active'
    and tp.deleted_at is null
  order by tp.target_year desc, tp.target_month desc, tp.created_at desc
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
