alter table public.schedules
add column if not exists break_start time,
add column if not exists break_end time,
add column if not exists peak_start time,
add column if not exists peak_end time,
add column if not exists shift_start time,
add column if not exists shift_end time;

create or replace function public.save_monthly_schedule_draft(
  p_schedule_date date,
  p_shift_type text,
  p_month_year text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_current_status text;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if p_schedule_date is null
     or nullif(trim(coalesce(p_shift_type, '')), '') is null
     or nullif(trim(coalesce(p_month_year, '')), '') is null then
    raise exception 'Data jadwal tidak lengkap';
  end if;

  select s.status
    into v_current_status
  from public.schedules s
  where s.promotor_id = v_user_id
    and s.schedule_date = p_schedule_date
  limit 1;

  if coalesce(v_current_status, 'draft') = 'submitted' then
    raise exception 'Jadwal submitted tidak bisa diedit';
  end if;

  insert into public.schedules (
    promotor_id,
    schedule_date,
    shift_type,
    status,
    month_year,
    rejection_reason,
    break_start,
    break_end,
    peak_start,
    peak_end
  ) values (
    v_user_id,
    p_schedule_date,
    trim(p_shift_type),
    'draft',
    trim(p_month_year),
    null,
    null,
    null,
    null,
    null
  )
  on conflict (promotor_id, schedule_date)
  do update set
    shift_type = excluded.shift_type,
    status = 'draft',
    month_year = excluded.month_year,
    rejection_reason = null,
    break_start = excluded.break_start,
    break_end = excluded.break_end,
    peak_start = excluded.peak_start,
    peak_end = excluded.peak_end,
    updated_at = now();

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.save_monthly_schedule_draft_bulk(
  p_month_year text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_month_year, '')), '') is null then
    raise exception 'Bulan jadwal wajib diisi';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Item jadwal kosong';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop
    if lower(trim(coalesce(v_item->>'shift_type', ''))) <> 'libur'
       and (
         nullif(v_item->>'break_start', '') is null
         or nullif(v_item->>'break_end', '') is null
       ) then
      raise exception 'Jam break wajib diisi untuk shift kerja';
    end if;

    if nullif(v_item->>'peak_start', '') is null
       or nullif(v_item->>'peak_end', '') is null then
      raise exception 'Jam ramai wajib diisi';
    end if;

    if lower(trim(coalesce(v_item->>'shift_type', ''))) <> 'libur'
       and (
         nullif(v_item->>'shift_start', '') is null
         or nullif(v_item->>'shift_end', '') is null
       ) then
      raise exception 'Jam shift wajib diisi';
    end if;

    insert into public.schedules (
      promotor_id,
      schedule_date,
      shift_type,
      status,
      month_year,
      rejection_reason,
      break_start,
      break_end,
      peak_start,
      peak_end,
      shift_start,
      shift_end
    ) values (
      v_user_id,
      nullif(v_item->>'schedule_date', '')::date,
      trim(coalesce(v_item->>'shift_type', '')),
      'draft',
      trim(p_month_year),
      null,
      case when lower(trim(coalesce(v_item->>'shift_type', ''))) = 'libur' then null else nullif(v_item->>'break_start', '')::time end,
      case when lower(trim(coalesce(v_item->>'shift_type', ''))) = 'libur' then null else nullif(v_item->>'break_end', '')::time end,
      nullif(v_item->>'peak_start', '')::time,
      nullif(v_item->>'peak_end', '')::time,
      case when lower(trim(coalesce(v_item->>'shift_type', ''))) = 'libur' then null else nullif(v_item->>'shift_start', '')::time end,
      case when lower(trim(coalesce(v_item->>'shift_type', ''))) = 'libur' then null else nullif(v_item->>'shift_end', '')::time end
    )
    on conflict (promotor_id, schedule_date)
    do update set
      shift_type = excluded.shift_type,
      status = 'draft',
      month_year = excluded.month_year,
      rejection_reason = null,
      break_start = excluded.break_start,
      break_end = excluded.break_end,
      peak_start = excluded.peak_start,
      peak_end = excluded.peak_end,
      shift_start = excluded.shift_start,
      shift_end = excluded.shift_end,
      updated_at = now();

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'success', true,
    'saved_count', v_count
  );
end;
$$;

create or replace function public.copy_previous_month_schedule(
  p_promotor_id uuid,
  p_target_month text
)
returns table (
  success boolean,
  message text,
  copied_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_previous_month text;
  v_copied_count integer := 0;
  v_target_date date;
  v_days_in_month integer;
  v_schedule_record record;
begin
  v_target_date := (p_target_month || '-01')::date;
  v_previous_month := to_char(v_target_date - interval '1 month', 'YYYY-MM');
  v_days_in_month := extract(day from (date_trunc('month', v_target_date) + interval '1 month' - interval '1 day'));

  if exists (
    select 1 from public.schedules
    where promotor_id = p_promotor_id
      and month_year = p_target_month
  ) then
    return query select false, 'Target month already has schedules. Delete them first.', 0;
    return;
  end if;

  if not exists (
    select 1 from public.schedules
    where promotor_id = p_promotor_id
      and month_year = v_previous_month
  ) then
    return query select false, 'No schedules found in previous month to copy.', 0;
    return;
  end if;

  for v_schedule_record in
    select
      shift_type,
      break_start,
      break_end,
      peak_start,
      peak_end,
      shift_start,
      shift_end,
      extract(day from schedule_date)::integer as day_num
    from public.schedules
    where promotor_id = p_promotor_id
      and month_year = v_previous_month
    order by schedule_date
  loop
    if v_schedule_record.day_num <= v_days_in_month then
      insert into public.schedules (
        promotor_id,
        schedule_date,
        shift_type,
        status,
        month_year,
        break_start,
        break_end,
        peak_start,
        peak_end,
        shift_start,
        shift_end
      ) values (
        p_promotor_id,
        (p_target_month || '-' || lpad(v_schedule_record.day_num::text, 2, '0'))::date,
        v_schedule_record.shift_type,
        'draft',
        p_target_month,
        v_schedule_record.break_start,
        v_schedule_record.break_end,
        v_schedule_record.peak_start,
        v_schedule_record.peak_end,
        v_schedule_record.shift_start,
        v_schedule_record.shift_end
      );
      v_copied_count := v_copied_count + 1;
    end if;
  end loop;

  return query select true, 'Successfully copied ' || v_copied_count || ' schedules from ' || v_previous_month, v_copied_count;
end;
$$;

create or replace function public.get_export_schedule_snapshot(
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select u.role
  into v_actor_role
  from public.users u
  where u.id = v_actor_id;

  if v_actor_role not in ('sator', 'spv') then
    raise exception 'Role ini belum didukung untuk export jadwal.';
  end if;

  return (
    with sator_scope as (
      select
        v_actor_id as sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name
      from public.users u
      where v_actor_role = 'sator'
        and u.id = v_actor_id
      union all
      select
        su.id as sator_id,
        coalesce(su.full_name, 'SATOR') as sator_name
      from public.hierarchy_spv_sator hss
      join public.users su on su.id = hss.sator_id
      where v_actor_role = 'spv'
        and hss.spv_id = v_actor_id
        and hss.active = true
    ),
    promotor_profile as (
      select distinct
        u.id as promotor_id,
        coalesce(u.full_name, 'Unknown') as promotor_name,
        coalesce(st.store_name, '-') as store_name,
        ss.sator_name,
        coalesce(u.area, 'default') as area
      from sator_scope ss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = ss.sator_id
       and hsp.active = true
      join public.users u
        on u.id = hsp.promotor_id
      left join lateral (
        select st.store_name
        from public.assignments_promotor_store aps
        join public.stores st on st.id = aps.store_id
        where aps.promotor_id = u.id
          and aps.active = true
        order by aps.created_at desc nulls last, aps.id desc
        limit 1
      ) st on true
    ),
    schedules_scope as (
      select
        s.promotor_id,
        s.schedule_date,
        s.shift_type,
        s.status,
        s.break_start,
        s.break_end,
        s.peak_start,
        s.peak_end,
        pp.promotor_name,
        pp.store_name,
        pp.sator_name,
        s.shift_start,
        s.shift_end
      from public.schedules s
      join promotor_profile pp on pp.promotor_id = s.promotor_id
      where s.schedule_date between p_start_date and p_end_date
    ),
    rows_payload as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', pp.promotor_id,
            'promotor_name', pp.promotor_name,
            'store_name', pp.store_name,
            'sator_name', pp.sator_name,
            'status', coalesce((
              select upper(ss.status)
              from schedules_scope ss
              where ss.promotor_id = pp.promotor_id
              order by ss.schedule_date desc
              limit 1
            ), 'BELUM_KIRIM'),
            'peak_hours', coalesce((
              select to_char(ss.peak_start, 'HH24:MI') || ' - ' || to_char(ss.peak_end, 'HH24:MI')
              from schedules_scope ss
              where ss.promotor_id = pp.promotor_id
                and ss.peak_start is not null
                and ss.peak_end is not null
              order by ss.schedule_date desc
              limit 1
            ), '-'),
            'schedule_map', coalesce((
              select jsonb_object_agg(
                to_char(ss.schedule_date, 'YYYY-MM-DD'),
                jsonb_build_object(
                  'clock_in', case when lower(coalesce(ss.shift_type, '')) = 'libur' then '' else coalesce(to_char(ss.shift_start, 'HH24:MI'), '') end,
                  'break_start', case when lower(coalesce(ss.shift_type, '')) = 'libur' then '' else coalesce(to_char(ss.break_start, 'HH24:MI'), '') end,
                  'break_end', case when lower(coalesce(ss.shift_type, '')) = 'libur' then '' else coalesce(to_char(ss.break_end, 'HH24:MI'), '') end,
                  'clock_out', case when lower(coalesce(ss.shift_type, '')) = 'libur' then '' else coalesce(to_char(ss.shift_end, 'HH24:MI'), '') end,
                  'shift_type', upper(coalesce(ss.shift_type, ''))
                )
              )
              from schedules_scope ss
              where ss.promotor_id = pp.promotor_id
            ), '{}'::jsonb)
          )
          order by pp.promotor_name
        ),
        '[]'::jsonb
      ) as data
      from promotor_profile pp
    )
    select jsonb_build_object(
      'rows', coalesce((select data from rows_payload), '[]'::jsonb)
    )
  );
end;
$$;

drop function if exists public.save_monthly_schedule_draft(date, text, text, time, time, time, time);
drop function if exists public.save_monthly_schedule_draft_bulk(text, jsonb, time, time);

grant execute on function public.save_monthly_schedule_draft(date, text, text) to authenticated;
grant execute on function public.save_monthly_schedule_draft_bulk(text, jsonb) to authenticated;
grant execute on function public.copy_previous_month_schedule(uuid, text) to authenticated;
grant execute on function public.get_export_schedule_snapshot(date, date) to authenticated;
