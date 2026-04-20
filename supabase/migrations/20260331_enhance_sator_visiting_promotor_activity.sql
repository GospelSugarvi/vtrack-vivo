create or replace function public.get_sator_store_promotor_monthly_activities(
  p_sator_id uuid,
  p_store_id uuid,
  p_date date default current_date
)
returns json
language sql
security definer
set search_path = public
as $$
  with scope_guard as (
    select 1
    from public.assignments_sator_store ass
    where ass.sator_id = p_sator_id
      and ass.store_id = p_store_id
      and ass.active = true
    limit 1
  ),
  current_period as (
    select
      tp.id as period_id,
      tp.start_date as month_start,
      tp.end_date as month_end
    from public.target_periods tp
    where p_date between tp.start_date and tp.end_date
      and tp.deleted_at is null
    order by
      case when tp.status = 'active' then 0 else 1 end,
      tp.start_date desc
    limit 1
  ),
  active_week as (
    select
      (cp.month_start + (wt.start_day - 1) * interval '1 day')::date as week_start,
      (cp.month_start + (wt.end_day - 1) * interval '1 day')::date as week_end
    from current_period cp
    join public.weekly_targets wt
      on coalesce(wt.period_id, cp.period_id) = cp.period_id
     and p_date between
       (cp.month_start + (wt.start_day - 1) * interval '1 day')::date
       and
       (cp.month_start + (wt.end_day - 1) * interval '1 day')::date
    order by
      case when wt.period_id = cp.period_id then 0 else 1 end,
      wt.week_number
    limit 1
  ),
  bounds as (
    select
      coalesce(cp.month_start, date_trunc('month', p_date)::date) as month_start,
      least(
        coalesce(
          cp.month_end,
          (date_trunc('month', p_date) + interval '1 month - 1 day')::date
        ),
        p_date
      ) as month_end,
      coalesce(aw.week_start, p_date) as week_start,
      least(coalesce(aw.week_end, p_date), p_date) as week_end
    from (select 1) seed
    left join current_period cp on true
    left join active_week aw on true
  ),
  active_promotors as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      coalesce(u.nickname, u.full_name) as promotor_name
    from public.assignments_promotor_store aps
    join public.users u on u.id = aps.promotor_id
    where aps.store_id = p_store_id
      and aps.active = true
      and u.status = 'active'
      and exists (select 1 from scope_guard)
    order by aps.promotor_id, aps.created_at desc nulls last
  ),
  rows as (
    select
      ap.promotor_id,
      ap.promotor_name,
      b.week_start,
      b.week_end,
      b.month_start,
      b.month_end,
      (
        select count(distinct a.attendance_date)::int
        from public.attendance a
        where a.user_id = ap.promotor_id
          and a.clock_in is not null
          and a.attendance_date >= b.week_start
          and a.attendance_date <= b.week_end
      ) as week_attendance_days,
      (
        select count(*)::int
        from public.sales_sell_out s
        where s.promotor_id = ap.promotor_id
          and s.store_id = p_store_id
          and s.deleted_at is null
          and s.transaction_date >= b.week_start
          and s.transaction_date <= b.week_end
      ) as week_sellout_count,
      (
        select count(*)::int
        from public.stock_movement_log sml
        where sml.moved_by = ap.promotor_id
          and coalesce(sml.to_store_id, sml.from_store_id) = p_store_id
          and (sml.moved_at at time zone 'Asia/Makassar')::date >= b.week_start
          and (sml.moved_at at time zone 'Asia/Makassar')::date <= b.week_end
      ) as week_stock_input_count,
      (
        select count(*)::int
        from public.promotion_reports pr
        where pr.promotor_id = ap.promotor_id
          and pr.store_id = p_store_id
          and (coalesce(pr.posted_at, pr.created_at) at time zone 'Asia/Makassar')::date >= b.week_start
          and (coalesce(pr.posted_at, pr.created_at) at time zone 'Asia/Makassar')::date <= b.week_end
      ) as week_promotion_count,
      (
        select count(*)::int
        from public.follower_reports fr
        where fr.promotor_id = ap.promotor_id
          and fr.store_id = p_store_id
          and (coalesce(fr.followed_at, fr.created_at) at time zone 'Asia/Makassar')::date >= b.week_start
          and (coalesce(fr.followed_at, fr.created_at) at time zone 'Asia/Makassar')::date <= b.week_end
      ) as week_follower_count,
      (
        select count(*)::int
        from public.allbrand_reports ar
        where ar.promotor_id = ap.promotor_id
          and ar.store_id = p_store_id
          and ar.report_date >= b.week_start
          and ar.report_date <= b.week_end
      ) as week_allbrand_count,
      (
        select count(*)::int
        from public.permission_requests pr
        where pr.promotor_id = ap.promotor_id
          and pr.request_date >= b.week_start
          and pr.request_date <= b.week_end
          and pr.status in ('approved_sator', 'approved_spv')
      ) as week_permission_count,
      (
        select count(distinct a.attendance_date)::int
        from public.attendance a
        where a.user_id = ap.promotor_id
          and a.clock_in is not null
          and a.attendance_date >= b.month_start
          and a.attendance_date <= b.month_end
      ) as month_attendance_days,
      (
        select count(*)::int
        from public.sales_sell_out s
        where s.promotor_id = ap.promotor_id
          and s.store_id = p_store_id
          and s.deleted_at is null
          and s.transaction_date >= b.month_start
          and s.transaction_date <= b.month_end
      ) as month_sellout_count,
      (
        select count(*)::int
        from public.stock_movement_log sml
        where sml.moved_by = ap.promotor_id
          and coalesce(sml.to_store_id, sml.from_store_id) = p_store_id
          and (sml.moved_at at time zone 'Asia/Makassar')::date >= b.month_start
          and (sml.moved_at at time zone 'Asia/Makassar')::date <= b.month_end
      ) as month_stock_input_count,
      (
        select count(*)::int
        from public.promotion_reports pr
        where pr.promotor_id = ap.promotor_id
          and pr.store_id = p_store_id
          and (coalesce(pr.posted_at, pr.created_at) at time zone 'Asia/Makassar')::date >= b.month_start
          and (coalesce(pr.posted_at, pr.created_at) at time zone 'Asia/Makassar')::date <= b.month_end
      ) as month_promotion_count,
      (
        select count(*)::int
        from public.follower_reports fr
        where fr.promotor_id = ap.promotor_id
          and fr.store_id = p_store_id
          and (coalesce(fr.followed_at, fr.created_at) at time zone 'Asia/Makassar')::date >= b.month_start
          and (coalesce(fr.followed_at, fr.created_at) at time zone 'Asia/Makassar')::date <= b.month_end
      ) as month_follower_count,
      (
        select count(*)::int
        from public.allbrand_reports ar
        where ar.promotor_id = ap.promotor_id
          and ar.store_id = p_store_id
          and ar.report_date >= b.month_start
          and ar.report_date <= b.month_end
      ) as month_allbrand_count,
      (
        select count(*)::int
        from public.permission_requests pr
        where pr.promotor_id = ap.promotor_id
          and pr.request_date >= b.month_start
          and pr.request_date <= b.month_end
          and pr.status in ('approved_sator', 'approved_spv')
      ) as month_permission_count
    from active_promotors ap
    cross join bounds b
  )
  select coalesce(
    json_agg(
      json_build_object(
        'promotor_id', r.promotor_id,
        'promotor_name', r.promotor_name,
        'week_start', r.week_start,
        'week_end', r.week_end,
        'month_start', r.month_start,
        'month_end', r.month_end,
        'week_attendance_days', coalesce(r.week_attendance_days, 0),
        'week_sellout_count', coalesce(r.week_sellout_count, 0),
        'week_stock_input_count', coalesce(r.week_stock_input_count, 0),
        'week_promotion_count', coalesce(r.week_promotion_count, 0),
        'week_follower_count', coalesce(r.week_follower_count, 0),
        'week_allbrand_count', coalesce(r.week_allbrand_count, 0),
        'week_permission_count', coalesce(r.week_permission_count, 0),
        'week_absence_count', greatest(
          ((r.week_end - r.week_start + 1)::int)
          - coalesce(r.week_attendance_days, 0)
          - coalesce(r.week_permission_count, 0),
          0
        ),
        'month_attendance_days', coalesce(r.month_attendance_days, 0),
        'month_sellout_count', coalesce(r.month_sellout_count, 0),
        'month_stock_input_count', coalesce(r.month_stock_input_count, 0),
        'month_promotion_count', coalesce(r.month_promotion_count, 0),
        'month_follower_count', coalesce(r.month_follower_count, 0),
        'month_allbrand_count', coalesce(r.month_allbrand_count, 0),
        'month_permission_count', coalesce(r.month_permission_count, 0),
        'month_absence_count', greatest(
          ((r.month_end - r.month_start + 1)::int)
          - coalesce(r.month_attendance_days, 0)
          - coalesce(r.month_permission_count, 0),
          0
        )
      )
      order by r.promotor_name
    ),
    '[]'::json
  )
  from rows r;
$$;

grant execute on function public.get_sator_store_promotor_monthly_activities(uuid, uuid, date) to authenticated;

create or replace function public.get_sator_pre_visit_snapshot(
  p_sator_id uuid,
  p_store_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_store jsonb := '{}'::jsonb;
  v_comments jsonb := '[]'::jsonb;
  v_performance jsonb := '{}'::jsonb;
  v_monthly_rows jsonb := '[]'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(p_sator_id)::jsonb, '[]'::jsonb)) as x(
      store_id uuid,
      store_name text,
      address text,
      area text,
      last_visit timestamptz,
      issue_count integer,
      priority integer,
      priority_score integer,
      priority_reasons jsonb
    )
    where x.store_id = p_store_id
  ) then
    raise exception 'Store is outside SATOR scope';
  end if;

  select to_jsonb(s)
  into v_store
  from (
    select st.id, st.store_name, st.address, st.area
    from public.stores st
    where st.id = p_store_id
    limit 1
  ) s;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', svc.id,
        'comment_text', svc.comment_text,
        'created_at', svc.created_at,
        'users', jsonb_build_object(
          'full_name', coalesce(u.full_name, 'User')
        )
      )
      order by svc.created_at desc
    ),
    '[]'::jsonb
  )
  into v_comments
  from (
    select *
    from public.store_visit_comments
    where store_id = p_store_id
      and (target_sator_id = p_sator_id or author_id = p_sator_id)
    order by created_at desc
    limit 12
  ) svc
  left join public.users u on u.id = svc.author_id;

  v_performance := coalesce(public.get_sator_visiting_briefing(p_sator_id, p_store_id, p_date)::jsonb, '{}'::jsonb);
  v_monthly_rows := coalesce(public.get_sator_store_promotor_monthly_activities(p_sator_id, p_store_id, p_date)::jsonb, '[]'::jsonb);

  return (
    with monthly_rows as (
      select *
      from jsonb_to_recordset(v_monthly_rows) as x(
        promotor_id uuid,
        week_start date,
        week_end date,
        month_start date,
        month_end date,
        week_attendance_days integer,
        week_sellout_count integer,
        week_stock_input_count integer,
        week_promotion_count integer,
        week_follower_count integer,
        week_allbrand_count integer,
        week_permission_count integer,
        week_absence_count integer,
        month_attendance_days integer,
        month_sellout_count integer,
        month_stock_input_count integer,
        month_promotion_count integer,
        month_follower_count integer,
        month_allbrand_count integer,
        month_permission_count integer,
        month_absence_count integer
      )
    ),
    promotors as (
      select coalesce(v_performance -> 'promotors', '[]'::jsonb) as data
    ),
    merged_promotors as (
      select coalesce(
        jsonb_agg(
          (to_jsonb(p) || coalesce(to_jsonb(mr), '{}'::jsonb))
          order by p.promotor_name
        ),
        '[]'::jsonb
      ) as data
      from jsonb_to_recordset((select data from promotors)) as p(
        promotor_id uuid,
        promotor_name text,
        target_nominal numeric,
        actual_nominal numeric,
        target_focus_units numeric,
        actual_focus_units numeric,
        achievement_pct numeric,
        latest_allbrand_total_units integer,
        latest_allbrand_cumulative_total_units integer,
        daily_target numeric,
        focus_target numeric,
        vast_target numeric,
        home_snapshot jsonb,
        active_week_snapshot jsonb,
        daily_special_rows jsonb,
        weekly_special_rows jsonb,
        monthly_special_rows jsonb,
        daily_target_all_type numeric,
        actual_daily_all_type numeric,
        achievement_daily_all_type_pct numeric,
        daily_focus_target numeric,
        actual_daily_focus numeric,
        achievement_daily_focus_pct numeric,
        weekly_target_all_type numeric,
        actual_weekly_all_type numeric,
        achievement_weekly_all_type_pct numeric,
        weekly_focus_target numeric,
        actual_weekly_focus numeric,
        achievement_weekly_focus_pct numeric,
        monthly_target_all_type numeric,
        actual_monthly_all_type numeric,
        achievement_monthly_all_type_pct numeric,
        monthly_focus_target numeric,
        actual_monthly_focus numeric,
        achievement_monthly_focus_pct numeric,
        active_week_number integer,
        active_week_start date,
        active_week_end date,
        period_start date,
        period_end date
      )
      left join monthly_rows mr on mr.promotor_id = p.promotor_id
    )
    select jsonb_build_object(
      'store', coalesce(v_store, '{}'::jsonb),
      'comments', coalesce(v_comments, '[]'::jsonb),
      'performance', (coalesce(v_performance, '{}'::jsonb) - 'promotors') || jsonb_build_object(
        'promotors', coalesce((select data from merged_promotors), '[]'::jsonb)
      )
    )
  );
end;
$$;

grant execute on function public.get_sator_pre_visit_snapshot(uuid, uuid, date) to authenticated;
