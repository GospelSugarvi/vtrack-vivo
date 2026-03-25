create or replace function public.get_sator_schedule_summary(
  p_sator_id uuid,
  p_month_year text
)
returns table (
  promotor_id uuid,
  promotor_name text,
  store_name text,
  status text,
  total_days integer,
  submitted_at timestamptz,
  last_updated timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with team_promotors as (
    select distinct hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.active = true
  ),
  current_store as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      st.store_name,
      aps.created_at
    from public.assignments_promotor_store aps
    join public.stores st
      on st.id = aps.store_id
    where aps.active = true
    order by aps.promotor_id, aps.created_at desc nulls last
  ),
  monthly_rollup as (
    select
      s.promotor_id,
      count(*)::integer as total_days,
      min(s.updated_at) filter (where s.status = 'submitted') as submitted_at,
      max(s.updated_at) as last_updated,
      case
        when bool_or(s.status = 'submitted') then 'submitted'
        when bool_or(s.status = 'rejected') then 'rejected'
        when bool_or(s.status = 'approved') then 'approved'
        when count(*) > 0 then 'draft'
        else 'belum_kirim'
      end as status
    from public.schedules s
    where s.month_year = p_month_year
    group by s.promotor_id
  )
  select
    u.id as promotor_id,
    u.full_name as promotor_name,
    coalesce(cs.store_name, '-') as store_name,
    coalesce(mr.status, 'belum_kirim') as status,
    coalesce(mr.total_days, 0) as total_days,
    mr.submitted_at,
    mr.last_updated
  from public.users u
  join team_promotors tp
    on tp.promotor_id = u.id
  left join current_store cs
    on cs.promotor_id = u.id
  left join monthly_rollup mr
    on mr.promotor_id = u.id
  where u.role = 'promotor'
    and u.status = 'active'
  order by u.full_name;
end;
$$;

grant execute on function public.get_sator_schedule_summary(uuid, text) to authenticated;

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
  total_days integer
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
    tr.total_days
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

create or replace function public.review_monthly_schedule(
  p_sator_id uuid,
  p_promotor_id uuid,
  p_month_year text,
  p_action text,
  p_rejection_reason text default null
)
returns table (
  success boolean,
  message text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new_status text;
  v_has_access boolean;
  v_submitted_count integer;
begin
  select exists (
    select 1
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.promotor_id = p_promotor_id
      and hsp.active = true
  ) into v_has_access;

  if not v_has_access then
    return query select false, 'Kamu tidak punya akses ke promotor ini.';
    return;
  end if;

  if p_action = 'approve' then
    v_new_status := 'approved';
  elsif p_action = 'reject' then
    v_new_status := 'rejected';
    if p_rejection_reason is null or trim(p_rejection_reason) = '' then
      return query select false, 'Alasan penolakan wajib diisi.';
      return;
    end if;
  else
    return query select false, 'Aksi tidak valid.';
    return;
  end if;

  select count(*)::integer
  into v_submitted_count
  from public.schedules s
  where s.promotor_id = p_promotor_id
    and s.month_year = p_month_year
    and s.status = 'submitted';

  if v_submitted_count = 0 then
    return query select false, 'Tidak ada jadwal submitted yang bisa direview.';
    return;
  end if;

  update public.schedules
  set status = v_new_status,
      rejection_reason = case
        when p_action = 'reject' then trim(p_rejection_reason)
        else null
      end,
      updated_at = now()
  where promotor_id = p_promotor_id
    and month_year = p_month_year
    and status = 'submitted';

  if p_action = 'approve' then
    return query select true, 'Jadwal berhasil di-approve.';
  else
    return query select true, 'Jadwal ditolak. Promotor bisa revisi lalu kirim ulang.';
  end if;
end;
$$;

grant execute on function public.review_monthly_schedule(uuid, uuid, text, text, text) to authenticated;
