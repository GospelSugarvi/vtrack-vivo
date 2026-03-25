create or replace function public.get_spv_home_snapshot(
  p_spv_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile jsonb := '{}'::jsonb;
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_active_week_number integer := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);
  v_active_week_percentage numeric := 25;
  v_month_start date := date_trunc('month', p_date)::date;
  v_week_start date := p_date - (extract(isodow from p_date)::int - 1);
  v_month_year text := to_char(p_date, 'YYYY-MM');
  v_now_wita_time time := (timezone('Asia/Makassar', now()))::time;
  v_total_sators integer := 0;
  v_total_promotors integer := 0;
  v_total_stores integer := 0;
  v_spv_target_sell_out_monthly numeric := 0;
  v_spv_target_focus_monthly integer := 0;
  v_team_target_sell_out_monthly numeric := 0;
  v_team_target_focus_monthly integer := 0;
  v_today_omzet numeric := 0;
  v_week_omzet numeric := 0;
  v_month_omzet numeric := 0;
  v_today_units integer := 0;
  v_week_focus_units integer := 0;
  v_month_focus_units integer := 0;
  v_schedule_total_tracked integer := 0;
  v_schedule_approved integer := 0;
  v_schedule_submitted integer := 0;
  v_schedule_not_sent integer := 0;
  v_attendance_checked_in_count integer := 0;
  v_attendance_working_count integer := 0;
  v_attendance_off_count integer := 0;
  v_attendance_late_count integer := 0;
  v_attendance_exception_count integer := 0;
  v_attendance_waiting_shift_count integer := 0;
  v_attendance_no_report_count integer := 0;
  v_checked_in_preview jsonb := '[]'::jsonb;
  v_attendance_attention_list jsonb := '[]'::jsonb;
  v_sator_cards jsonb := '[]'::jsonb;
  v_sator record;
  v_card jsonb;
begin
  select jsonb_build_object(
    'full_name', coalesce(u.full_name, 'SPV'),
    'area', coalesce(u.area, '-'),
    'role', 'SPV'
  )
  into v_profile
  from public.users u
  where u.id = p_spv_id;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
  order by tp.start_date desc
  limit 1;

  if v_period_id is not null then
    select wt.week_number, wt.percentage
    into v_active_week_number, v_active_week_percentage
    from public.weekly_targets wt
    where wt.period_id = v_period_id
      and extract(day from p_date)::int between wt.start_day and wt.end_day
    order by wt.week_number
    limit 1;

    if v_active_week_percentage is null then
      select wt.week_number, wt.percentage
      into v_active_week_number, v_active_week_percentage
      from public.weekly_targets wt
      where wt.period_id = v_period_id
        and wt.week_number = greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1)
      limit 1;
    end if;
  end if;

  v_active_week_percentage := coalesce(v_active_week_percentage, 25);

  with sator_scope as (
    select u.id as sator_id
    from public.hierarchy_spv_sator hss
    join public.users u on u.id = hss.sator_id
    where hss.spv_id = p_spv_id
      and hss.active = true
      and u.deleted_at is null
  ),
  promotor_scope as (
    select distinct hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    join sator_scope ss on ss.sator_id = hsp.sator_id
    where hsp.active = true
  ),
  store_scope as (
    select distinct aps.store_id
    from public.assignments_promotor_store aps
    join promotor_scope ps on ps.promotor_id = aps.promotor_id
    where aps.active = true
  )
  select
    (select count(*) from sator_scope),
    (select count(*) from promotor_scope),
    (select count(*) from store_scope)
  into v_total_sators, v_total_promotors, v_total_stores;

  if v_period_id is not null then
    select
      coalesce(ut.target_sell_out, 0),
      coalesce(ut.target_fokus_total, 0)
    into v_spv_target_sell_out_monthly, v_spv_target_focus_monthly
    from public.user_targets ut
    where ut.user_id = p_spv_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc nulls last
    limit 1;

    with sator_scope as (
      select hss.sator_id
      from public.hierarchy_spv_sator hss
      where hss.spv_id = p_spv_id
        and hss.active = true
    )
    select
      coalesce(sum(ut.target_sell_out), 0),
      coalesce(sum(ut.target_fokus_total), 0)
    into v_team_target_sell_out_monthly, v_team_target_focus_monthly
    from public.user_targets ut
    join sator_scope ss on ss.sator_id = ut.user_id
    where ut.period_id = v_period_id;

    if coalesce(v_spv_target_sell_out_monthly, 0) > 0 then
      v_team_target_sell_out_monthly := v_spv_target_sell_out_monthly;
    end if;
    if coalesce(v_spv_target_focus_monthly, 0) > 0 then
      v_team_target_focus_monthly := v_spv_target_focus_monthly;
    end if;
  end if;

  with promotor_scope as (
    select distinct hsp.promotor_id
    from public.hierarchy_spv_sator hss
    join public.hierarchy_sator_promotor hsp
      on hsp.sator_id = hss.sator_id
     and hsp.active = true
    where hss.spv_id = p_spv_id
      and hss.active = true
  )
  select
    coalesce(sum(case when s.transaction_date = p_date then s.price_at_transaction else 0 end), 0),
    coalesce(sum(case when s.transaction_date >= v_week_start then s.price_at_transaction else 0 end), 0),
    coalesce(sum(s.price_at_transaction), 0),
    coalesce(sum(case when s.transaction_date = p_date then 1 else 0 end), 0),
    coalesce(sum(case when s.transaction_date >= v_week_start and (coalesce(p.is_focus, false) or coalesce(p.is_fokus, false)) then 1 else 0 end), 0),
    coalesce(sum(case when coalesce(p.is_focus, false) or coalesce(p.is_fokus, false) then 1 else 0 end), 0)
  into
    v_today_omzet,
    v_week_omzet,
    v_month_omzet,
    v_today_units,
    v_week_focus_units,
    v_month_focus_units
  from public.sales_sell_out s
  join promotor_scope ps on ps.promotor_id = s.promotor_id
  left join public.product_variants pv on pv.id = s.variant_id
  left join public.products p on p.id = pv.product_id
  where s.transaction_date between v_month_start and p_date
    and s.deleted_at is null
    and coalesce(s.is_chip_sale, false) = false;

  with sator_scope as (
    select u.id as sator_id
    from public.hierarchy_spv_sator hss
    join public.users u on u.id = hss.sator_id
    where hss.spv_id = p_spv_id
      and hss.active = true
      and u.deleted_at is null
  ),
  schedule_scope as (
    select ss.sator_id, sch.status
    from sator_scope ss
    left join lateral public.get_sator_schedule_summary(ss.sator_id, v_month_year) sch on true
  )
  select
    coalesce(count(*) filter (where status is not null), 0),
    coalesce(count(*) filter (where status = 'approved'), 0),
    coalesce(count(*) filter (where status = 'submitted'), 0),
    coalesce(count(*) filter (where status = 'belum_kirim'), 0)
  into
    v_schedule_total_tracked,
    v_schedule_approved,
    v_schedule_submitted,
    v_schedule_not_sent
  from schedule_scope;

  with sator_scope as (
    select
      hss.sator_id,
      su.full_name as sator_name
    from public.hierarchy_spv_sator hss
    join public.users su on su.id = hss.sator_id
    where hss.spv_id = p_spv_id
      and hss.active = true
      and su.deleted_at is null
  ),
  promotor_scope as (
    select
      hsp.promotor_id,
      ss.sator_id,
      ss.sator_name
    from public.hierarchy_sator_promotor hsp
    join sator_scope ss on ss.sator_id = hsp.sator_id
    where hsp.active = true
  ),
  promotor_assignments as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      aps.store_id,
      coalesce(st.store_name, '-') as store_name,
      coalesce(u.area, '-') as promotor_area
    from public.assignments_promotor_store aps
    join promotor_scope ps on ps.promotor_id = aps.promotor_id
    join public.users u on u.id = aps.promotor_id
    left join public.stores st on st.id = aps.store_id
    where aps.active = true
    order by aps.promotor_id, aps.created_at desc nulls last, aps.store_id
  ),
  today_schedule as (
    select distinct on (s.promotor_id)
      s.promotor_id,
      s.shift_type,
      s.status
    from public.schedules s
    join promotor_scope ps on ps.promotor_id = s.promotor_id
    where s.schedule_date = p_date
    order by s.promotor_id, s.updated_at desc nulls last, s.created_at desc nulls last
  ),
  today_attendance as (
    select distinct on (a.user_id)
      a.user_id,
      a.clock_in,
      nullif(to_jsonb(a) ->> 'main_attendance_status', '') as main_attendance_status,
      nullif(to_jsonb(a) ->> 'report_category', '') as report_category
    from public.attendance a
    join promotor_scope ps on ps.promotor_id = a.user_id
    where a.attendance_date = p_date
    order by a.user_id, a.created_at desc nulls last, a.clock_in desc nulls last
  ),
  monitor as (
    select
      ps.sator_id,
      ps.sator_name,
      ps.promotor_id,
      u.full_name as promotor_name,
      coalesce(pa.store_name, '-') as store_name,
      sc.shift_type,
      sc.status as schedule_status,
      shift.start_time as shift_start,
      shift.end_time as shift_end,
      ta.clock_in as clock_in_at,
      case
        when coalesce(ta.report_category, '') <> '' then ta.report_category
        when ta.main_attendance_status = 'late' then 'late'
        when ta.clock_in is not null then 'normal'
        else ''
      end as attendance_category,
      case
        when sc.shift_type = 'libur' then 'Libur'
        when sc.shift_type is not null then initcap(sc.shift_type) || ' ' || public.get_shift_display(sc.shift_type, coalesce(pa.promotor_area, 'default'))
        else 'Belum ada jadwal'
      end as shift_label,
      case
        when ta.clock_in is not null then 'checked_in'
        when coalesce(ta.report_category, '') in ('travel', 'special_permission', 'system_issue', 'sick', 'leave', 'management_holiday') then 'exception'
        when sc.shift_type = 'libur' then 'off'
        when sc.promotor_id is null then 'no_schedule'
        when coalesce(sc.status, '') <> 'approved' then 'schedule_pending'
        when shift.start_time is not null and v_now_wita_time < shift.start_time then 'waiting_shift'
        else 'no_report'
      end as status_key,
      case
        when ta.clock_in is not null and ta.main_attendance_status = 'late' then 'Sudah masuk · terlambat'
        when ta.clock_in is not null then 'Sudah masuk kerja'
        when coalesce(ta.report_category, '') = 'travel' then 'Perjalanan dinas'
        when coalesce(ta.report_category, '') = 'special_permission' then 'Izin atasan'
        when coalesce(ta.report_category, '') = 'system_issue' then 'Kendala sistem'
        when coalesce(ta.report_category, '') = 'sick' then 'Sakit'
        when coalesce(ta.report_category, '') = 'leave' then 'Izin'
        when coalesce(ta.report_category, '') = 'management_holiday' then 'Libur management'
        when sc.shift_type = 'libur' then 'Libur hari ini'
        when sc.promotor_id is null then 'Jadwal hari ini belum ada'
        when sc.status = 'submitted' then 'Jadwal menunggu approval'
        when sc.status = 'draft' then 'Jadwal masih draft'
        when sc.status = 'rejected' then 'Jadwal ditolak'
        when shift.start_time is not null and v_now_wita_time < shift.start_time then 'Masuk ' || to_char(shift.start_time, 'HH24:MI')
        else 'Belum ada laporan masuk kerja'
      end as status_reason
    from promotor_scope ps
    join public.users u on u.id = ps.promotor_id
    left join promotor_assignments pa on pa.promotor_id = ps.promotor_id
    left join today_schedule sc on sc.promotor_id = ps.promotor_id
    left join lateral (
      select ss.start_time, ss.end_time
      from public.shift_settings ss
      where ss.shift_type = sc.shift_type
        and ss.active = true
        and ss.area in (coalesce(pa.promotor_area, 'default'), 'default')
      order by case when ss.area = coalesce(pa.promotor_area, 'default') then 0 else 1 end
      limit 1
    ) shift on sc.shift_type is not null and sc.shift_type <> 'libur'
    left join today_attendance ta on ta.user_id = ps.promotor_id
    where u.deleted_at is null
  )
  select
    coalesce(count(*) filter (where status_key = 'checked_in'), 0),
    coalesce(count(*) filter (where schedule_status = 'approved' and shift_type <> 'libur'), 0),
    coalesce(count(*) filter (where status_key = 'off'), 0),
    coalesce(count(*) filter (where attendance_category = 'late'), 0),
    coalesce(count(*) filter (where status_key = 'exception'), 0),
    coalesce(count(*) filter (where status_key = 'waiting_shift'), 0),
    coalesce(count(*) filter (where status_key in ('no_report', 'schedule_pending', 'no_schedule')), 0)
  into
    v_attendance_checked_in_count,
    v_attendance_working_count,
    v_attendance_off_count,
    v_attendance_late_count,
    v_attendance_exception_count,
    v_attendance_waiting_shift_count,
    v_attendance_no_report_count
  from monitor;

  with sator_scope as (
    select
      hss.sator_id,
      su.full_name as sator_name
    from public.hierarchy_spv_sator hss
    join public.users su on su.id = hss.sator_id
    where hss.spv_id = p_spv_id
      and hss.active = true
      and su.deleted_at is null
  ),
  promotor_scope as (
    select
      hsp.promotor_id,
      ss.sator_id,
      ss.sator_name
    from public.hierarchy_sator_promotor hsp
    join sator_scope ss on ss.sator_id = hsp.sator_id
    where hsp.active = true
  ),
  promotor_assignments as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      coalesce(st.store_name, '-') as store_name,
      coalesce(u.area, '-') as promotor_area
    from public.assignments_promotor_store aps
    join promotor_scope ps on ps.promotor_id = aps.promotor_id
    join public.users u on u.id = aps.promotor_id
    left join public.stores st on st.id = aps.store_id
    where aps.active = true
    order by aps.promotor_id, aps.created_at desc nulls last, aps.store_id
  ),
  today_schedule as (
    select distinct on (s.promotor_id)
      s.promotor_id,
      s.shift_type,
      s.status
    from public.schedules s
    join promotor_scope ps on ps.promotor_id = s.promotor_id
    where s.schedule_date = p_date
    order by s.promotor_id, s.updated_at desc nulls last, s.created_at desc nulls last
  ),
  today_attendance as (
    select distinct on (a.user_id)
      a.user_id,
      a.clock_in,
      a.main_attendance_status,
      a.report_category
    from public.attendance a
    join promotor_scope ps on ps.promotor_id = a.user_id
    where a.attendance_date = p_date
    order by a.user_id, a.created_at desc nulls last, a.clock_in desc nulls last
  ),
  monitor as (
    select
      ps.sator_id,
      ps.sator_name,
      u.full_name as promotor_name,
      coalesce(pa.store_name, '-') as store_name,
      sc.shift_type,
      sc.status as schedule_status,
      shift.start_time as shift_start,
      ta.clock_in as clock_in_at,
      case
        when coalesce(ta.report_category, '') <> '' then ta.report_category
        when ta.main_attendance_status = 'late' then 'late'
        when ta.clock_in is not null then 'normal'
        else ''
      end as attendance_category,
      case
        when sc.shift_type = 'libur' then 'Libur'
        when sc.shift_type is not null then initcap(sc.shift_type) || ' ' || public.get_shift_display(sc.shift_type, coalesce(pa.promotor_area, 'default'))
        else 'Belum ada jadwal'
      end as shift_label,
      case
        when ta.clock_in is not null then 'checked_in'
        when coalesce(ta.report_category, '') in ('travel', 'special_permission', 'system_issue', 'sick', 'leave', 'management_holiday') then 'exception'
        when sc.shift_type = 'libur' then 'off'
        when sc.promotor_id is null then 'no_schedule'
        when coalesce(sc.status, '') <> 'approved' then 'schedule_pending'
        when shift.start_time is not null and v_now_wita_time < shift.start_time then 'waiting_shift'
        else 'no_report'
      end as status_key,
      case
        when ta.clock_in is not null and ta.main_attendance_status = 'late' then 'Sudah masuk · terlambat'
        when ta.clock_in is not null then 'Sudah masuk kerja'
        when coalesce(ta.report_category, '') = 'travel' then 'Perjalanan dinas'
        when coalesce(ta.report_category, '') = 'special_permission' then 'Izin atasan'
        when coalesce(ta.report_category, '') = 'system_issue' then 'Kendala sistem'
        when coalesce(ta.report_category, '') = 'sick' then 'Sakit'
        when coalesce(ta.report_category, '') = 'leave' then 'Izin'
        when coalesce(ta.report_category, '') = 'management_holiday' then 'Libur management'
        when sc.shift_type = 'libur' then 'Libur hari ini'
        when sc.promotor_id is null then 'Jadwal hari ini belum ada'
        when sc.status = 'submitted' then 'Jadwal menunggu approval'
        when sc.status = 'draft' then 'Jadwal masih draft'
        when sc.status = 'rejected' then 'Jadwal ditolak'
        when shift.start_time is not null and v_now_wita_time < shift.start_time then 'Masuk ' || to_char(shift.start_time, 'HH24:MI')
        else 'Belum ada laporan masuk kerja'
      end as status_reason
    from promotor_scope ps
    join public.users u on u.id = ps.promotor_id
    left join promotor_assignments pa on pa.promotor_id = ps.promotor_id
    left join today_schedule sc on sc.promotor_id = ps.promotor_id
    left join lateral (
      select ss.start_time, ss.end_time
      from public.shift_settings ss
      where ss.shift_type = sc.shift_type
        and ss.active = true
        and ss.area in (coalesce(pa.promotor_area, 'default'), 'default')
      order by case when ss.area = coalesce(pa.promotor_area, 'default') then 0 else 1 end
      limit 1
    ) shift on sc.shift_type is not null and sc.shift_type <> 'libur'
    left join today_attendance ta on ta.user_id = ps.promotor_id
    join sator_scope ss on ss.sator_id = ps.sator_id
  ),
  checked_in_preview as (
    select
      promotor_name,
      sator_name,
      store_name,
      shift_label,
      to_char(timezone('Asia/Makassar', clock_in_at), 'HH24:MI') as clock_in_time,
      attendance_category
    from monitor
    where status_key = 'checked_in'
    order by clock_in_at desc nulls last, promotor_name
    limit 6
  ),
  attention_rows as (
    select
      promotor_name,
      sator_name,
      store_name,
      shift_label,
      status_key,
      status_reason,
      attendance_category,
      case
        when clock_in_at is null then null
        else to_char(timezone('Asia/Makassar', clock_in_at), 'HH24:MI')
      end as clock_in_time
    from monitor
    where status_key <> 'off'
      and (
        status_key <> 'checked_in'
        or attendance_category = 'late'
      )
    order by
      case status_key
        when 'no_report' then 0
        when 'schedule_pending' then 1
        when 'no_schedule' then 2
        when 'exception' then 3
        when 'waiting_shift' then 4
        when 'checked_in' then 5
        else 6
      end,
      shift_start nulls first,
      promotor_name
    limit 8
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'promotor_name', promotor_name,
            'sator_name', sator_name,
            'store_name', store_name,
            'shift_label', shift_label,
            'clock_in_time', clock_in_time,
            'attendance_category', attendance_category
          )
        )
        from checked_in_preview
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'promotor_name', promotor_name,
            'sator_name', sator_name,
            'store_name', store_name,
            'shift_label', shift_label,
            'status_key', status_key,
            'status_reason', status_reason,
            'attendance_category', attendance_category,
            'clock_in_time', clock_in_time
          )
        )
        from attention_rows
      ),
      '[]'::jsonb
    )
  into v_checked_in_preview, v_attendance_attention_list;

  for v_sator in
    with sator_scope as (
      select
        u.id as sator_id,
        u.full_name as sator_name,
        coalesce(u.area, '-') as sator_area
      from public.hierarchy_spv_sator hss
      join public.users u on u.id = hss.sator_id
      where hss.spv_id = p_spv_id
        and hss.active = true
        and u.deleted_at is null
    ),
    promotor_counts as (
      select
        hsp.sator_id,
        count(*)::int as promotor_count
      from public.hierarchy_sator_promotor hsp
      join sator_scope ss on ss.sator_id = hsp.sator_id
      where hsp.active = true
      group by hsp.sator_id
    )
    select
      ss.sator_id,
      ss.sator_name,
      ss.sator_area,
      coalesce(pc.promotor_count, 0) as promotor_count
    from sator_scope ss
    left join promotor_counts pc on pc.sator_id = ss.sator_id
    order by ss.sator_name
  loop
    declare
      v_target_sell_out_monthly numeric := 0;
      v_target_focus_monthly integer := 0;
      v_actual_sell_out_daily numeric := 0;
      v_actual_sell_out_weekly numeric := 0;
      v_actual_sell_out_monthly numeric := 0;
      v_actual_focus_daily integer := 0;
      v_actual_focus_weekly integer := 0;
      v_actual_focus_monthly integer := 0;
      v_pending_jadwal_count integer := 0;
      v_visit_count integer := 0;
      v_top_promotors jsonb := '[]'::jsonb;
      v_achievement_pct_monthly numeric := 0;
      v_attendance_present_count integer := 0;
      v_attendance_working_count integer := 0;
      v_attendance_late_count integer := 0;
      v_attendance_no_report_count integer := 0;
      v_attendance_waiting_shift_count integer := 0;
      v_attendance_exception_count integer := 0;
      v_attendance_off_count integer := 0;
      v_attendance_watchlist jsonb := '[]'::jsonb;
    begin
      if v_period_id is not null then
        select
          coalesce(ut.target_sell_out, 0),
          coalesce(ut.target_fokus_total, 0)
        into v_target_sell_out_monthly, v_target_focus_monthly
        from public.user_targets ut
        where ut.user_id = v_sator.sator_id
          and ut.period_id = v_period_id
        order by ut.updated_at desc nulls last
        limit 1;
      end if;

      with promotor_scope as (
        select hsp.promotor_id
        from public.hierarchy_sator_promotor hsp
        where hsp.sator_id = v_sator.sator_id
          and hsp.active = true
      )
      select
        coalesce(sum(case when s.transaction_date = p_date then s.price_at_transaction else 0 end), 0),
        coalesce(sum(case when s.transaction_date >= v_week_start then s.price_at_transaction else 0 end), 0),
        coalesce(sum(s.price_at_transaction), 0),
        coalesce(sum(case when s.transaction_date = p_date and (coalesce(p.is_focus, false) or coalesce(p.is_fokus, false)) then 1 else 0 end), 0),
        coalesce(sum(case when s.transaction_date >= v_week_start and (coalesce(p.is_focus, false) or coalesce(p.is_fokus, false)) then 1 else 0 end), 0),
        coalesce(sum(case when coalesce(p.is_focus, false) or coalesce(p.is_fokus, false) then 1 else 0 end), 0)
      into
        v_actual_sell_out_daily,
        v_actual_sell_out_weekly,
        v_actual_sell_out_monthly,
        v_actual_focus_daily,
        v_actual_focus_weekly,
        v_actual_focus_monthly
      from public.sales_sell_out s
      join promotor_scope ps on ps.promotor_id = s.promotor_id
      left join public.product_variants pv on pv.id = s.variant_id
      left join public.products p on p.id = pv.product_id
      where s.transaction_date between v_month_start and p_date
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false;

      select count(*)
      into v_pending_jadwal_count
      from public.get_sator_schedule_summary(v_sator.sator_id, v_month_year) sch
      where sch.status = 'submitted';

      select count(*)
      into v_visit_count
      from public.store_visits sv
      where sv.sator_id = v_sator.sator_id
        and sv.visit_date = p_date;

      with ranked as (
        select
          u.full_name as name,
          count(*)::int as units
        from public.sales_sell_out s
        join public.users u on u.id = s.promotor_id
        join public.hierarchy_sator_promotor hsp
          on hsp.promotor_id = s.promotor_id
         and hsp.sator_id = v_sator.sator_id
         and hsp.active = true
        where s.transaction_date = p_date
          and s.deleted_at is null
          and coalesce(s.is_chip_sale, false) = false
        group by u.full_name
        order by units desc, u.full_name
        limit 3
      )
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'name', ranked.name,
            'units', ranked.units
          )
        ),
        '[]'::jsonb
      )
      into v_top_promotors
      from ranked;

      with promotor_scope as (
        select hsp.promotor_id
        from public.hierarchy_sator_promotor hsp
        where hsp.sator_id = v_sator.sator_id
          and hsp.active = true
      ),
      promotor_assignments as (
        select distinct on (aps.promotor_id)
          aps.promotor_id,
          coalesce(st.store_name, '-') as store_name,
          coalesce(u.area, '-') as promotor_area
        from public.assignments_promotor_store aps
        join promotor_scope ps on ps.promotor_id = aps.promotor_id
        join public.users u on u.id = aps.promotor_id
        left join public.stores st on st.id = aps.store_id
        where aps.active = true
        order by aps.promotor_id, aps.created_at desc nulls last, aps.store_id
      ),
      today_schedule as (
        select distinct on (s.promotor_id)
          s.promotor_id,
          s.shift_type,
          s.status
        from public.schedules s
        join promotor_scope ps on ps.promotor_id = s.promotor_id
        where s.schedule_date = p_date
        order by s.promotor_id, s.updated_at desc nulls last, s.created_at desc nulls last
      ),
      today_attendance as (
        select distinct on (a.user_id)
          a.user_id,
          a.clock_in,
          nullif(to_jsonb(a) ->> 'main_attendance_status', '') as main_attendance_status,
          nullif(to_jsonb(a) ->> 'report_category', '') as report_category
        from public.attendance a
        join promotor_scope ps on ps.promotor_id = a.user_id
        where a.attendance_date = p_date
        order by a.user_id, a.created_at desc nulls last, a.clock_in desc nulls last
      ),
      monitor as (
        select
          u.full_name as promotor_name,
          coalesce(pa.store_name, '-') as store_name,
          sc.shift_type,
          sc.status as schedule_status,
          shift.start_time as shift_start,
          ta.clock_in as clock_in_at,
          case
            when coalesce(ta.report_category, '') <> '' then ta.report_category
            when ta.main_attendance_status = 'late' then 'late'
            when ta.clock_in is not null then 'normal'
            else ''
          end as attendance_category,
          case
            when sc.shift_type = 'libur' then 'Libur'
            when sc.shift_type is not null then initcap(sc.shift_type) || ' ' || public.get_shift_display(sc.shift_type, coalesce(pa.promotor_area, 'default'))
            else 'Belum ada jadwal'
          end as shift_label,
          case
            when ta.clock_in is not null then 'checked_in'
            when coalesce(ta.report_category, '') in ('travel', 'special_permission', 'system_issue', 'sick', 'leave', 'management_holiday') then 'exception'
            when sc.shift_type = 'libur' then 'off'
            when sc.promotor_id is null then 'no_schedule'
            when coalesce(sc.status, '') <> 'approved' then 'schedule_pending'
            when shift.start_time is not null and v_now_wita_time < shift.start_time then 'waiting_shift'
            else 'no_report'
          end as status_key,
          case
            when ta.clock_in is not null and ta.main_attendance_status = 'late' then 'Sudah masuk · terlambat'
            when ta.clock_in is not null then 'Sudah masuk kerja'
            when coalesce(ta.report_category, '') = 'travel' then 'Perjalanan dinas'
            when coalesce(ta.report_category, '') = 'special_permission' then 'Izin atasan'
            when coalesce(ta.report_category, '') = 'system_issue' then 'Kendala sistem'
            when coalesce(ta.report_category, '') = 'sick' then 'Sakit'
            when coalesce(ta.report_category, '') = 'leave' then 'Izin'
            when coalesce(ta.report_category, '') = 'management_holiday' then 'Libur management'
            when sc.shift_type = 'libur' then 'Libur hari ini'
            when sc.promotor_id is null then 'Jadwal hari ini belum ada'
            when sc.status = 'submitted' then 'Jadwal menunggu approval'
            when sc.status = 'draft' then 'Jadwal masih draft'
            when sc.status = 'rejected' then 'Jadwal ditolak'
            when shift.start_time is not null and v_now_wita_time < shift.start_time then 'Masuk ' || to_char(shift.start_time, 'HH24:MI')
            else 'Belum ada laporan masuk kerja'
          end as status_reason
        from promotor_scope ps
        join public.users u on u.id = ps.promotor_id
        left join promotor_assignments pa on pa.promotor_id = ps.promotor_id
        left join today_schedule sc on sc.promotor_id = ps.promotor_id
        left join lateral (
          select ss.start_time, ss.end_time
          from public.shift_settings ss
          where ss.shift_type = sc.shift_type
            and ss.active = true
            and ss.area in (coalesce(pa.promotor_area, 'default'), 'default')
          order by case when ss.area = coalesce(pa.promotor_area, 'default') then 0 else 1 end
          limit 1
        ) shift on sc.shift_type is not null and sc.shift_type <> 'libur'
        left join today_attendance ta on ta.user_id = ps.promotor_id
      ),
      watchlist as (
        select
          promotor_name,
          store_name,
          shift_label,
          status_key,
          status_reason
        from monitor
        where status_key in ('no_report', 'schedule_pending', 'no_schedule', 'exception', 'waiting_shift')
        order by
          case status_key
            when 'no_report' then 0
            when 'schedule_pending' then 1
            when 'no_schedule' then 2
            when 'exception' then 3
            when 'waiting_shift' then 4
            else 5
          end,
          shift_start nulls first,
          promotor_name
        limit 3
      )
      select
        coalesce(count(*) filter (where status_key = 'checked_in'), 0),
        coalesce(count(*) filter (where schedule_status = 'approved' and shift_type <> 'libur'), 0),
        coalesce(count(*) filter (where attendance_category = 'late'), 0),
        coalesce(count(*) filter (where status_key in ('no_report', 'schedule_pending', 'no_schedule')), 0),
        coalesce(count(*) filter (where status_key = 'waiting_shift'), 0),
        coalesce(count(*) filter (where status_key = 'exception'), 0),
        coalesce(count(*) filter (where status_key = 'off'), 0),
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'promotor_name', promotor_name,
                'store_name', store_name,
                'shift_label', shift_label,
                'status_key', status_key,
                'status_reason', status_reason
              )
            )
            from watchlist
          ),
          '[]'::jsonb
        )
      into
        v_attendance_present_count,
        v_attendance_working_count,
        v_attendance_late_count,
        v_attendance_no_report_count,
        v_attendance_waiting_shift_count,
        v_attendance_exception_count,
        v_attendance_off_count,
        v_attendance_watchlist
      from monitor;

      if v_target_sell_out_monthly > 0 then
        v_achievement_pct_monthly := round(
          v_actual_sell_out_monthly * 100.0 / v_target_sell_out_monthly,
          0
        );
      end if;

      v_card := jsonb_build_object(
        'sator_id', v_sator.sator_id,
        'sator_name', v_sator.sator_name,
        'sator_area', v_sator.sator_area,
        'promotor_count', v_sator.promotor_count,
        'target_sell_out_daily', round((v_target_sell_out_monthly * v_active_week_percentage / 100.0) / 6.0),
        'target_sell_out_weekly', round(v_target_sell_out_monthly * v_active_week_percentage / 100.0),
        'target_sell_out_monthly', round(v_target_sell_out_monthly),
        'actual_sell_out_daily', round(v_actual_sell_out_daily),
        'actual_sell_out_weekly', round(v_actual_sell_out_weekly),
        'actual_sell_out_monthly', round(v_actual_sell_out_monthly),
        'target_focus_daily', round((v_target_focus_monthly * v_active_week_percentage / 100.0) / 6.0),
        'target_focus_weekly', round(v_target_focus_monthly * v_active_week_percentage / 100.0),
        'target_focus_monthly', v_target_focus_monthly,
        'actual_focus_daily', v_actual_focus_daily,
        'actual_focus_weekly', v_actual_focus_weekly,
        'actual_focus_monthly', v_actual_focus_monthly,
        'pending_jadwal_count', v_pending_jadwal_count,
        'visit_count', v_visit_count,
        'top_promotors', v_top_promotors,
        'achievement_pct_monthly', v_achievement_pct_monthly,
        'attendance_present_count', v_attendance_present_count,
        'attendance_working_count', v_attendance_working_count,
        'attendance_late_count', v_attendance_late_count,
        'attendance_no_report_count', v_attendance_no_report_count,
        'attendance_waiting_shift_count', v_attendance_waiting_shift_count,
        'attendance_exception_count', v_attendance_exception_count,
        'attendance_off_count', v_attendance_off_count,
        'attendance_watchlist', v_attendance_watchlist
      );

      v_sator_cards := v_sator_cards || jsonb_build_array(v_card);
    end;
  end loop;

  select coalesce(
    jsonb_agg(card order by coalesce((card ->> 'achievement_pct_monthly')::numeric, 0) desc, card ->> 'sator_name'),
    '[]'::jsonb
  )
  into v_sator_cards
  from jsonb_array_elements(v_sator_cards) card;

  return jsonb_build_object(
    'profile', v_profile,
    'counts', jsonb_build_object(
      'sators', v_total_sators,
      'promotors', v_total_promotors,
      'stores', v_total_stores
    ),
    'team_target_data', jsonb_build_object(
      'target_sell_out_monthly', round(v_team_target_sell_out_monthly),
      'target_sell_out_weekly', round(v_team_target_sell_out_monthly * v_active_week_percentage / 100.0),
      'target_sell_out_daily', round((v_team_target_sell_out_monthly * v_active_week_percentage / 100.0) / 6.0),
      'target_focus_monthly', v_team_target_focus_monthly,
      'target_focus_weekly', round(v_team_target_focus_monthly * v_active_week_percentage / 100.0),
      'target_focus_daily', round((v_team_target_focus_monthly * v_active_week_percentage / 100.0) / 6.0),
      'active_week_number', v_active_week_number,
      'active_week_percentage', v_active_week_percentage,
      'working_days', 6
    ),
    'metrics', jsonb_build_object(
      'today_omzet', round(v_today_omzet),
      'week_omzet', round(v_week_omzet),
      'month_omzet', round(v_month_omzet),
      'today_units', v_today_units,
      'week_focus_units', v_week_focus_units,
      'month_focus_units', v_month_focus_units
    ),
    'schedule_summary', jsonb_build_object(
      'total_tracked', v_schedule_total_tracked,
      'approved', v_schedule_approved,
      'submitted', v_schedule_submitted,
      'belum_kirim', v_schedule_not_sent
    ),
    'attendance_summary', jsonb_build_object(
      'checked_in_count', v_attendance_checked_in_count,
      'working_count', v_attendance_working_count,
      'off_count', v_attendance_off_count,
      'late_count', v_attendance_late_count,
      'exception_count', v_attendance_exception_count,
      'waiting_shift_count', v_attendance_waiting_shift_count,
      'no_report_count', v_attendance_no_report_count,
      'checked_in_preview', v_checked_in_preview,
      'attention_list', v_attendance_attention_list
    ),
    'sator_cards', v_sator_cards
  );
end;
$function$;

grant execute on function public.get_spv_home_snapshot(uuid, date) to authenticated;
