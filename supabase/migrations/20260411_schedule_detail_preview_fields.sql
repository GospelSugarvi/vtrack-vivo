create or replace function public.get_promotor_schedule_detail(
  p_promotor_id uuid,
  p_month_year text
)
returns table (
  schedule_date date,
  shift_type text,
  status text,
  rejection_reason text,
  promotor_name text,
  store_name text,
  total_days integer,
  break_start time,
  break_end time,
  peak_start time,
  peak_end time,
  shift_start time,
  shift_end time
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with current_store as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      st.store_name,
      aps.created_at
    from public.assignments_promotor_store aps
    join public.stores st
      on st.id = aps.store_id
    where aps.promotor_id = p_promotor_id
      and aps.active = true
    order by aps.promotor_id, aps.created_at desc nulls last
  ),
  total_rows as (
    select count(*)::integer as total_days
    from public.schedules
    where promotor_id = p_promotor_id
      and month_year = p_month_year
  )
  select
    s.schedule_date,
    s.shift_type,
    s.status,
    s.rejection_reason,
    u.full_name as promotor_name,
    coalesce(cs.store_name, '-') as store_name,
    tr.total_days,
    s.break_start,
    s.break_end,
    s.peak_start,
    s.peak_end,
    s.shift_start,
    s.shift_end
  from public.schedules s
  join public.users u
    on u.id = s.promotor_id
  left join current_store cs
    on cs.promotor_id = u.id
  cross join total_rows tr
  where s.promotor_id = p_promotor_id
    and s.month_year = p_month_year
  order by s.schedule_date;
end;
$$;

grant execute on function public.get_promotor_schedule_detail(uuid, text) to authenticated;

create or replace function public.get_schedule_detail_snapshot(
  p_promotor_id uuid,
  p_month_year text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_has_access boolean := false;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    raise exception 'User profile not found';
  end if;

  if v_actor.role = 'admin'::public.user_role or public.is_elevated_user() then
    v_has_access := true;
  elsif v_actor.role = 'promotor'::public.user_role then
    v_has_access := p_promotor_id = v_actor_id;
  elsif v_actor.role = 'sator'::public.user_role then
    select exists(
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = v_actor_id
        and hsp.promotor_id = p_promotor_id
        and hsp.active = true
    )
    into v_has_access;
  elsif v_actor.role = 'spv'::public.user_role then
    select exists(
      select 1
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
        and hsp.active = true
        and hsp.promotor_id = p_promotor_id
    )
    into v_has_access;
  end if;

  if not v_has_access then
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'current_user', jsonb_build_object(
      'id', v_actor.id,
      'full_name', coalesce(v_actor.full_name, 'User'),
      'role', coalesce(v_actor.role::text, '')
    ),
    'schedules', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.schedule_date)
      from public.get_promotor_schedule_detail(p_promotor_id, p_month_year) s
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'author_id', c.author_id,
          'author_name', c.author_name,
          'author_role', c.author_role,
          'message', c.message,
          'created_at', c.created_at,
          'month_year', c.month_year
        )
        order by c.created_at
      )
      from public.schedule_review_comments c
      where c.promotor_id = p_promotor_id
        and c.month_year = p_month_year
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_schedule_detail_snapshot(uuid, text) to authenticated;
