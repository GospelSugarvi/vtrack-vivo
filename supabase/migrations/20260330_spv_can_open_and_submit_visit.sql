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
  v_actor_role text;
  v_store jsonb := '{}'::jsonb;
  v_comments jsonb := '[]'::jsonb;
  v_performance jsonb := '{}'::jsonb;
  v_monthly_rows jsonb := '[]'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role
  into v_actor_role
  from public.users
  where id = v_actor_id;

  if not (
    public.is_elevated_user()
    or p_sator_id = v_actor_id
    or (
      coalesce(v_actor_role, '') = 'spv'
      and exists (
        select 1
        from public.hierarchy_spv_sator hss
        where hss.spv_id = v_actor_id
          and hss.sator_id = p_sator_id
          and hss.active = true
      )
    )
  ) then
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
      and (target_sator_id = p_sator_id or author_id = p_sator_id or author_id = v_actor_id)
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
        month_attendance_days integer,
        month_sellout_count integer,
        month_stock_input_count integer,
        month_promotion_count integer,
        month_follower_count integer,
        month_allbrand_count integer
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

create or replace function public.create_scoped_visit_comment(
  p_store_id uuid,
  p_comment_text text,
  p_target_sator_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_target_sator_id uuid := coalesce(p_target_sator_id, v_actor_id);
  v_row public.store_visit_comments%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role
  into v_actor_role
  from public.users
  where id = v_actor_id;

  if trim(coalesce(p_comment_text, '')) = '' then
    raise exception 'Comment is required';
  end if;

  if coalesce(v_actor_role, '') = 'sator' and v_target_sator_id <> v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if coalesce(v_actor_role, '') = 'spv' and not public.is_elevated_user() then
    if not exists (
      select 1
      from public.hierarchy_spv_sator hss
      where hss.spv_id = v_actor_id
        and hss.sator_id = v_target_sator_id
        and hss.active = true
    ) then
      raise exception 'SATOR is outside SPV scope';
    end if;
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(v_target_sator_id)::jsonb, '[]'::jsonb)) as x(
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

  insert into public.store_visit_comments (
    store_id,
    author_id,
    target_sator_id,
    comment_text
  )
  values (
    p_store_id,
    v_actor_id,
    v_target_sator_id,
    trim(p_comment_text)
  )
  returning *
  into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'comment_text', v_row.comment_text,
    'created_at', v_row.created_at
  );
end;
$$;

grant execute on function public.create_scoped_visit_comment(uuid, text, uuid) to authenticated;

create or replace function public.submit_scoped_visit(
  p_store_id uuid,
  p_photo_urls jsonb,
  p_notes text default null,
  p_visit_at timestamptz default now(),
  p_target_sator_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_target_sator_id uuid := coalesce(p_target_sator_id, v_actor_id);
  v_visit_date date := (p_visit_at at time zone 'Asia/Makassar')::date;
  v_first_photo text;
  v_second_photo text;
  v_row public.store_visits%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role
  into v_actor_role
  from public.users
  where id = v_actor_id;

  if coalesce(jsonb_array_length(coalesce(p_photo_urls, '[]'::jsonb)), 0) <= 0 then
    raise exception 'Minimal 1 foto visit diperlukan.';
  end if;

  if coalesce(v_actor_role, '') = 'sator' and v_target_sator_id <> v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if coalesce(v_actor_role, '') = 'spv' and not public.is_elevated_user() then
    if not exists (
      select 1
      from public.hierarchy_spv_sator hss
      where hss.spv_id = v_actor_id
        and hss.sator_id = v_target_sator_id
        and hss.active = true
    ) then
      raise exception 'SATOR is outside SPV scope';
    end if;
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(v_target_sator_id)::jsonb, '[]'::jsonb)) as x(
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

  select value
  into v_first_photo
  from jsonb_array_elements_text(coalesce(p_photo_urls, '[]'::jsonb))
  limit 1;

  select value
  into v_second_photo
  from jsonb_array_elements_text(coalesce(p_photo_urls, '[]'::jsonb))
  offset 1
  limit 1;

  insert into public.store_visits (
    store_id,
    sator_id,
    visit_date,
    check_in_time,
    check_in_photo,
    check_out_photo,
    notes,
    follow_up
  )
  values (
    p_store_id,
    v_target_sator_id,
    v_visit_date,
    p_visit_at,
    v_first_photo,
    v_second_photo,
    nullif(trim(coalesce(p_notes, '')), ''),
    null
  )
  returning *
  into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'visit_date', v_row.visit_date,
    'check_in_time', v_row.check_in_time
  );
end;
$$;

grant execute on function public.submit_scoped_visit(uuid, jsonb, text, timestamptz, uuid) to authenticated;
