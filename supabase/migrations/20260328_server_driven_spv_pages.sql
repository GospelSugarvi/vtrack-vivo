create or replace function public.get_spv_permission_approval_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
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

  return jsonb_build_object(
    'requests',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pr.id,
          'request_date', pr.request_date,
          'request_type', pr.request_type,
          'reason', pr.reason,
          'note', pr.note,
          'photo_url', pr.photo_url,
          'status', pr.status,
          'created_at', pr.created_at,
          'sator_comment', pr.sator_comment,
          'spv_comment', pr.spv_comment,
          'promotor_name', coalesce(u.full_name, 'Promotor'),
          'sator_name', coalesce(sator.full_name, 'SATOR')
        )
        order by pr.created_at desc
      )
      from public.permission_requests pr
      left join public.users u
        on u.id = pr.promotor_id
      left join public.users sator
        on sator.id = pr.sator_id
      where pr.spv_id = v_actor_id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_spv_permission_approval_snapshot() to authenticated;

create or replace function public.get_spv_permission_pending_count()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_total integer := 0;
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

  select count(*)::int
  into v_total
  from public.permission_requests pr
  where pr.spv_id = v_actor_id
    and pr.status = 'approved_sator';

  return jsonb_build_object('pending_count', v_total);
end;
$$;

grant execute on function public.get_spv_permission_pending_count() to authenticated;

create or replace function public.get_spv_chip_monitor_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
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

  return jsonb_build_object(
    'rows',
    coalesce((
      with sator_scope as (
        select hss.sator_id
        from public.hierarchy_spv_sator hss
        where hss.spv_id = v_actor_id
          and hss.active = true
      )
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'status', r.status,
          'requested_at', r.requested_at,
          'promotor_name', coalesce(p.full_name, 'Promotor'),
          'store_name', coalesce(st.store_name, '-')
        )
        order by r.requested_at desc
      )
      from public.stock_chip_requests r
      left join public.users p
        on p.id = r.promotor_id
      left join public.stores st
        on st.id = r.store_id
      where r.sator_id in (select sator_id from sator_scope)
      limit 100
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_spv_chip_monitor_snapshot() to authenticated;

create or replace function public.get_spv_stock_management_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_area text := '-';
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

  select coalesce(nullif(trim(u.area), ''), '-')
  into v_area
  from public.users u
  where u.id = v_actor_id;

  return jsonb_build_object(
    'area_name', v_area,
    'stores',
    coalesce((
      with store_scope as (
        select st.id, st.store_name
        from public.stores st
        where st.area = v_area
        order by st.store_name
      ),
      chip_rows as (
        select
          s.store_id,
          coalesce(p.full_name, '') as promotor_name,
          coalesce(a.full_name, '') as approver_name
        from public.stok s
        left join public.users p on p.id = s.promotor_id
        left join public.users a on a.id = s.chip_approved_by
        where s.store_id in (select id from store_scope)
          and s.tipe_stok = 'chip'
          and s.is_sold = false
      ),
      pending_rows as (
        select r.store_id, count(*)::int as pending_chip_count
        from public.stock_chip_requests r
        where r.store_id in (select id from store_scope)
          and r.status = 'pending'
        group by r.store_id
      )
      select jsonb_agg(
        jsonb_build_object(
          'store_id', ss.id,
          'store_name', ss.store_name,
          'chip_count', coalesce((select count(*)::int from chip_rows cr where cr.store_id = ss.id), 0),
          'pending_chip_count', coalesce(pr.pending_chip_count, 0),
          'promotor_names', coalesce((
            select jsonb_agg(x.promotor_name order by x.promotor_name)
            from (
              select distinct cr.promotor_name
              from chip_rows cr
              where cr.store_id = ss.id
                and cr.promotor_name <> ''
            ) x
          ), '[]'::jsonb),
          'approver_names', coalesce((
            select jsonb_agg(x.approver_name order by x.approver_name)
            from (
              select distinct cr.approver_name
              from chip_rows cr
              where cr.store_id = ss.id
                and cr.approver_name <> ''
            ) x
          ), '[]'::jsonb)
        )
        order by coalesce((select count(*)::int from chip_rows cr where cr.store_id = ss.id), 0) desc, ss.store_name
      )
      from store_scope ss
      left join pending_rows pr on pr.store_id = ss.id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_spv_stock_management_snapshot() to authenticated;

create or replace function public.get_spv_visiting_monitor_snapshot(
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

  return jsonb_build_object(
    'rows',
    coalesce((
      with sator_scope as (
        select
          hss.sator_id,
          coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'SATOR')) as name
        from public.hierarchy_spv_sator hss
        join public.users u on u.id = hss.sator_id
        where hss.spv_id = v_actor_id
          and hss.active = true
      ),
      assigned as (
        select ass.sator_id, count(distinct ass.store_id)::int as total_stores
        from public.assignments_sator_store ass
        where ass.sator_id in (select sator_id from sator_scope)
          and ass.active = true
        group by ass.sator_id
      ),
      visited as (
        select sv.sator_id, count(distinct sv.store_id)::int as visited_stores
        from public.store_visits sv
        where sv.sator_id in (select sator_id from sator_scope)
          and sv.visit_date = p_date
        group by sv.sator_id
      )
      select jsonb_agg(
        jsonb_build_object(
          'name', ss.name,
          'total_stores', coalesce(a.total_stores, 0),
          'visited_stores', coalesce(v.visited_stores, 0),
          'pct', case
            when coalesce(a.total_stores, 0) > 0
            then round((coalesce(v.visited_stores, 0)::numeric * 100) / a.total_stores::numeric, 1)
            else 0
          end
        )
        order by coalesce(v.visited_stores, 0) desc, ss.name
      )
      from sator_scope ss
      left join assigned a on a.sator_id = ss.sator_id
      left join visited v on v.sator_id = ss.sator_id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_spv_visiting_monitor_snapshot(date) to authenticated;

create or replace function public.get_spv_attendance_monitor_snapshot(
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
    with sator_scope as (
      select
        hss.sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name
      from public.hierarchy_spv_sator hss
      join public.users u on u.id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
    ),
    promotor_scope as (
      select
        hsp.sator_id,
        hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id in (select sator_id from sator_scope)
        and hsp.active = true
    ),
    promotor_users as (
      select
        ps.sator_id,
        u.id as promotor_id,
        coalesce(u.full_name, 'Promotor') as promotor_name,
        coalesce(nullif(trim(u.area), ''), 'default') as area
      from promotor_scope ps
      join public.users u on u.id = ps.promotor_id
      where u.deleted_at is null
    ),
    latest_store as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        coalesce(st.store_name, '-') as store_name
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      where aps.promotor_id in (select promotor_id from promotor_users)
        and aps.active = true
      order by aps.promotor_id, aps.created_at desc
    ),
    latest_schedule as (
      select distinct on (s.promotor_id)
        s.promotor_id,
        coalesce(s.shift_type, '') as shift_type,
        coalesce(s.status, '') as schedule_status
      from public.schedules s
      where s.promotor_id in (select promotor_id from promotor_users)
        and s.schedule_date = p_date
      order by s.promotor_id, coalesce(s.updated_at, s.created_at) desc, s.created_at desc
    ),
    latest_attendance as (
      select distinct on (a.user_id)
        a.user_id as promotor_id,
        a.clock_in,
        coalesce(a.main_attendance_status, '') as main_attendance_status,
        coalesce(a.report_category, '') as report_category
      from public.attendance a
      where a.user_id in (select promotor_id from promotor_users)
        and a.attendance_date = p_date
      order by a.user_id, a.created_at desc
    ),
    merged as (
      select
        pu.sator_id,
        ss.sator_name,
        pu.promotor_id,
        pu.promotor_name,
        coalesce(ls.store_name, '-') as store_name,
        coalesce(sc.shift_type, '') as shift_type,
        coalesce(sc.schedule_status, '') as schedule_status,
        att.clock_in,
        case
          when coalesce(att.report_category, '') <> '' then att.report_category
          when coalesce(att.main_attendance_status, '') = 'late' then 'late'
          when att.clock_in is not null then 'normal'
          else ''
        end as attendance_category,
        shift_match.start_time
      from promotor_users pu
      join sator_scope ss on ss.sator_id = pu.sator_id
      left join latest_store ls on ls.promotor_id = pu.promotor_id
      left join latest_schedule sc on sc.promotor_id = pu.promotor_id
      left join latest_attendance att on att.promotor_id = pu.promotor_id
      left join lateral (
        select sh.start_time, sh.end_time
        from public.shift_settings sh
        where sh.active = true
          and sh.shift_type = coalesce(sc.shift_type, '')
          and sh.area in (pu.area, 'default')
        order by case when sh.area = pu.area then 0 else 1 end
        limit 1
      ) shift_match on true
    ),
    rows_payload as (
      select
        m.sator_id,
        m.sator_name,
        m.promotor_id,
        m.promotor_name,
        m.store_name,
        case
          when m.shift_type = '' then 'Belum ada jadwal'
          when m.shift_type = 'libur' then 'Libur'
          when m.start_time is null then initcap(m.shift_type)
          else initcap(m.shift_type) || ' ' || to_char(m.start_time, 'HH24:MI') || '-' || to_char(coalesce((select sh.end_time from public.shift_settings sh where sh.shift_type = m.shift_type and sh.active = true and sh.area in ((select area from promotor_users pu where pu.promotor_id = m.promotor_id), 'default') order by case when sh.area = (select area from promotor_users pu where pu.promotor_id = m.promotor_id) then 0 else 1 end limit 1), m.start_time), 'HH24:MI')
        end as shift_label,
        case
          when m.clock_in is not null then 'checked_in'
          when m.attendance_category in ('travel','special_permission','system_issue','sick','leave','management_holiday') then 'exception'
          when m.shift_type = 'libur' then 'off'
          when m.shift_type = '' then 'no_schedule'
          when m.schedule_status <> 'approved' then 'schedule_pending'
          when m.start_time is not null and localtime < m.start_time then 'waiting_shift'
          else 'no_report'
        end as status_key,
        case
          when m.clock_in is not null and m.attendance_category = 'late' then 'Sudah masuk · terlambat'
          when m.clock_in is not null then 'Sudah masuk kerja'
          when m.attendance_category = 'travel' then 'Perjalanan Dinas'
          when m.attendance_category = 'special_permission' then 'Izin Atasan'
          when m.attendance_category = 'system_issue' then 'Kendala Sistem'
          when m.attendance_category = 'sick' then 'Sakit'
          when m.attendance_category = 'leave' then 'Izin'
          when m.attendance_category = 'management_holiday' then 'Libur Management'
          when m.shift_type = 'libur' then 'Libur hari ini'
          when m.shift_type = '' then 'Jadwal hari ini belum ada'
          when m.schedule_status <> 'approved' then 'Jadwal belum approved'
          when m.start_time is not null and localtime < m.start_time then 'Masuk ' || to_char(m.start_time, 'HH24:MI')
          else 'Belum ada laporan masuk kerja'
        end as status_reason,
        m.attendance_category,
        case when m.clock_in is null then '' else to_char(m.clock_in at time zone 'Asia/Makassar', 'HH24:MI') end as clock_in_time,
        case
          when m.clock_in is not null and m.attendance_category <> 'late' then 0
          when m.clock_in is not null and m.attendance_category = 'late' then 1
          when m.start_time is not null and localtime < m.start_time then 2
          when m.attendance_category in ('travel','special_permission','system_issue','sick','leave','management_holiday') then 3
          when m.shift_type = 'libur' then 4
          when m.shift_type <> '' and m.schedule_status = 'approved' then 5
          when m.shift_type <> '' and m.schedule_status <> 'approved' then 6
          when m.shift_type = '' then 7
          else 8
        end as sort_order
      from merged m
    )
    select jsonb_build_object(
      'tabs', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', ss.sator_id,
            'name', ss.sator_name
          )
          order by ss.sator_name
        )
        from sator_scope ss
      ), '[]'::jsonb),
      'rows', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'sator_id', rp.sator_id,
            'sator_name', rp.sator_name,
            'promotor_id', rp.promotor_id,
            'promotor_name', rp.promotor_name,
            'store_name', rp.store_name,
            'shift_label', rp.shift_label,
            'status_key', rp.status_key,
            'status_reason', rp.status_reason,
            'attendance_category', rp.attendance_category,
            'clock_in_time', rp.clock_in_time
          )
          order by rp.sort_order, rp.promotor_name
        )
        from rows_payload rp
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_spv_attendance_monitor_snapshot(date) to authenticated;

create or replace function public.get_spv_schedule_monitor_snapshot(
  p_month_year text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_requested_month text := coalesce(nullif(trim(p_month_year), ''), to_char(current_date, 'YYYY-MM'));
  v_current_month text := to_char(current_date, 'YYYY-MM');
  v_target_month text := v_requested_month;
  v_next_month text := to_char((to_date(v_requested_month || '-01', 'YYYY-MM-DD') + interval '1 month')::date, 'YYYY-MM');
  v_has_submitted boolean := false;
  v_next_has_submitted boolean := false;
  v_requested_date date := to_date(v_requested_month || '-01', 'YYYY-MM-DD');
  v_inspect_date date;
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

  with rows_for_month as (
    with sator_scope as (
      select
        hss.sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name
      from public.hierarchy_spv_sator hss
      join public.users u on u.id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
    )
    select
      ss.sator_id,
      ss.sator_name,
      sch.promotor_id,
      sch.promotor_name,
      sch.store_name,
      sch.status,
      sch.total_days,
      sch.submitted_at,
      sch.last_updated
    from sator_scope ss
    left join lateral public.get_sator_schedule_summary(ss.sator_id, v_requested_month) sch
      on true
  )
  select bool_or(status = 'submitted')
  into v_has_submitted
  from rows_for_month;

  if v_requested_month = v_current_month and not coalesce(v_has_submitted, false) then
    with rows_for_month as (
      with sator_scope as (
        select hss.sator_id
        from public.hierarchy_spv_sator hss
        where hss.spv_id = v_actor_id
          and hss.active = true
      )
      select sch.status
      from sator_scope ss
      left join lateral public.get_sator_schedule_summary(ss.sator_id, v_next_month) sch
        on true
    )
    select bool_or(status = 'submitted')
    into v_next_has_submitted
    from rows_for_month;

    if coalesce(v_next_has_submitted, false) then
      v_target_month := v_next_month;
      v_requested_date := to_date(v_target_month || '-01', 'YYYY-MM-DD');
    end if;
  end if;

  v_inspect_date := make_date(
    extract(year from v_requested_date)::int,
    extract(month from v_requested_date)::int,
    least(
      extract(day from current_date)::int,
      extract(day from (date_trunc('month', v_requested_date) + interval '1 month - 1 day'))::int
    )
  );

  return (
    with sator_scope as (
      select
        hss.sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name
      from public.hierarchy_spv_sator hss
      join public.users u on u.id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
    ),
    base_rows as (
      select
        ss.sator_id,
        ss.sator_name,
        sch.promotor_id,
        sch.promotor_name,
        sch.store_name,
        sch.status,
        sch.total_days,
        sch.submitted_at,
        sch.last_updated
      from sator_scope ss
      left join lateral public.get_sator_schedule_summary(ss.sator_id, v_target_month) sch
        on true
    ),
    today_shift as (
      select distinct on (s.promotor_id)
        s.promotor_id,
        coalesce(s.shift_type, '') as today_shift_type,
        coalesce(s.status, '') as today_shift_status
      from public.schedules s
      where s.promotor_id in (
        select br.promotor_id
        from base_rows br
        where br.promotor_id is not null
      )
        and s.schedule_date = v_inspect_date
      order by s.promotor_id, coalesce(s.updated_at, s.created_at) desc, s.created_at desc
    )
    select jsonb_build_object(
      'month_year', v_target_month,
      'rows', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'sator_id', br.sator_id,
            'sator_name', br.sator_name,
            'promotor_id', br.promotor_id,
            'promotor_name', br.promotor_name,
            'store_name', br.store_name,
            'status', br.status,
            'total_days', br.total_days,
            'submitted_at', br.submitted_at,
            'last_updated', br.last_updated,
            'today_shift_type', coalesce(ts.today_shift_type, ''),
            'today_shift_status', coalesce(ts.today_shift_status, '')
          )
          order by
            case br.status
              when 'submitted' then 0
              when 'belum_kirim' then 1
              when 'rejected' then 2
              when 'approved' then 3
              when 'draft' then 4
              else 5
            end,
            br.promotor_name
        )
        from base_rows br
        left join today_shift ts on ts.promotor_id = br.promotor_id
        where br.promotor_id is not null
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_spv_schedule_monitor_snapshot(text) to authenticated;
