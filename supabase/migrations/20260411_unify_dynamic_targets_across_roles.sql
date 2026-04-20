create or replace function public.get_sator_dynamic_target_rollup(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  with current_period as (
    select
      tp.id as period_id,
      tp.period_name,
      tp.start_date,
      tp.end_date
    from public.target_periods tp
    where p_date between tp.start_date and tp.end_date
      and tp.deleted_at is null
    order by tp.start_date desc, tp.created_at desc
    limit 1
  ),
  promotor_scope as (
    select hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.active = true
  ),
  store_scope as (
    select distinct aps.store_id
    from public.assignments_promotor_store aps
    join promotor_scope ps on ps.promotor_id = aps.promotor_id
    where aps.active = true
  ),
  daily_rows as (
    select
      ps.promotor_id,
      d.active_week_number,
      d.active_week_start,
      d.active_week_end,
      d.working_days,
      coalesce(d.target_daily_all_type, 0)::numeric as target_daily_all_type,
      coalesce(d.actual_daily_all_type, 0)::numeric as actual_daily_all_type,
      coalesce(d.target_weekly_all_type, 0)::numeric as target_weekly_all_type,
      coalesce(d.actual_weekly_all_type, 0)::numeric as actual_weekly_all_type,
      coalesce(d.target_daily_focus, 0)::numeric as target_daily_focus,
      coalesce(d.actual_daily_focus, 0)::numeric as actual_daily_focus,
      coalesce(d.target_weekly_focus, 0)::numeric as target_weekly_focus,
      coalesce(d.actual_weekly_focus, 0)::numeric as actual_weekly_focus
    from promotor_scope ps
    left join lateral public.get_daily_target_dashboard(ps.promotor_id, p_date) d
      on true
  ),
  monthly_rows as (
    select
      ps.promotor_id,
      coalesce(m.target_omzet, 0)::numeric as target_omzet,
      coalesce(m.actual_omzet, 0)::numeric as actual_omzet,
      coalesce(m.target_fokus_total, 0)::numeric as target_fokus_total,
      coalesce(m.actual_fokus_total, 0)::numeric as actual_fokus_total
    from promotor_scope ps
    left join current_period cp on true
    left join lateral public.get_target_dashboard(ps.promotor_id, cp.period_id) m
      on true
  ),
  counts as (
    select
      (select count(*) from promotor_scope)::int as promotor_count,
      (select count(*) from store_scope)::int as store_count
  ),
  daily_totals as (
    select
      coalesce(sum(dr.target_daily_all_type), 0)::numeric as target_sellout,
      coalesce(sum(dr.actual_daily_all_type), 0)::numeric as actual_sellout,
      coalesce(sum(dr.target_daily_focus), 0)::numeric as target_fokus,
      coalesce(sum(dr.actual_daily_focus), 0)::numeric as actual_fokus,
      coalesce(sum(dr.target_weekly_all_type), 0)::numeric as target_sellout_weekly,
      coalesce(sum(dr.actual_weekly_all_type), 0)::numeric as actual_sellout_weekly,
      coalesce(sum(dr.target_weekly_focus), 0)::numeric as target_fokus_weekly,
      coalesce(sum(dr.actual_weekly_focus), 0)::numeric as actual_fokus_weekly,
      max(dr.active_week_number)::int as active_week_number,
      max(dr.active_week_start) as active_week_start,
      max(dr.active_week_end) as active_week_end,
      max(dr.working_days)::int as remaining_workdays
    from daily_rows dr
  ),
  monthly_totals as (
    select
      coalesce(sum(mr.target_omzet), 0)::numeric as target_sellout,
      coalesce(sum(mr.actual_omzet), 0)::numeric as actual_sellout,
      coalesce(sum(mr.target_fokus_total), 0)::numeric as target_fokus,
      coalesce(sum(mr.actual_fokus_total), 0)::numeric as actual_fokus
    from monthly_rows mr
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'id', cp.period_id,
      'period_name', cp.period_name,
      'start_date', cp.start_date,
      'end_date', cp.end_date
    ),
    'counts', jsonb_build_object(
      'promotors', coalesce(c.promotor_count, 0),
      'stores', coalesce(c.store_count, 0)
    ),
    'daily', jsonb_build_object(
      'target_sellout', coalesce(dt.target_sellout, 0),
      'actual_sellout', coalesce(dt.actual_sellout, 0),
      'target_fokus', coalesce(dt.target_fokus, 0),
      'actual_fokus', coalesce(dt.actual_fokus, 0)
    ),
    'weekly', jsonb_build_object(
      'week_index', coalesce(dt.active_week_number, 0),
      'week_start', dt.active_week_start,
      'week_end', dt.active_week_end,
      'target_sellout', coalesce(dt.target_sellout_weekly, 0),
      'actual_sellout', coalesce(dt.actual_sellout_weekly, 0),
      'target_fokus', coalesce(dt.target_fokus_weekly, 0),
      'actual_fokus', coalesce(dt.actual_fokus_weekly, 0)
    ),
    'monthly', jsonb_build_object(
      'target_sellout', coalesce(mt.target_sellout, 0),
      'actual_sellout', coalesce(mt.actual_sellout, 0),
      'target_fokus', coalesce(mt.target_fokus, 0),
      'actual_fokus', coalesce(mt.actual_fokus, 0)
    ),
    'remaining_workdays', coalesce(dt.remaining_workdays, 0)
  )
  from current_period cp
  cross join counts c
  left join daily_totals dt on true
  left join monthly_totals mt on true;
$function$;

create or replace function public.get_spv_dynamic_target_rollup(
  p_spv_id uuid,
  p_date date default current_date
)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  with current_period as (
    select
      tp.id as period_id,
      tp.period_name,
      tp.start_date,
      tp.end_date
    from public.target_periods tp
    where p_date between tp.start_date and tp.end_date
      and tp.deleted_at is null
    order by tp.start_date desc, tp.created_at desc
    limit 1
  ),
  sator_scope as (
    select hss.sator_id
    from public.hierarchy_spv_sator hss
    where hss.spv_id = p_spv_id
      and hss.active = true
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
  ),
  daily_rows as (
    select
      ps.promotor_id,
      d.active_week_number,
      d.active_week_start,
      d.active_week_end,
      d.working_days,
      coalesce(d.target_daily_all_type, 0)::numeric as target_daily_all_type,
      coalesce(d.actual_daily_all_type, 0)::numeric as actual_daily_all_type,
      coalesce(d.target_weekly_all_type, 0)::numeric as target_weekly_all_type,
      coalesce(d.actual_weekly_all_type, 0)::numeric as actual_weekly_all_type,
      coalesce(d.target_daily_focus, 0)::numeric as target_daily_focus,
      coalesce(d.actual_daily_focus, 0)::numeric as actual_daily_focus,
      coalesce(d.target_weekly_focus, 0)::numeric as target_weekly_focus,
      coalesce(d.actual_weekly_focus, 0)::numeric as actual_weekly_focus
    from promotor_scope ps
    left join lateral public.get_daily_target_dashboard(ps.promotor_id, p_date) d
      on true
  ),
  monthly_rows as (
    select
      ps.promotor_id,
      coalesce(m.target_omzet, 0)::numeric as target_omzet,
      coalesce(m.actual_omzet, 0)::numeric as actual_omzet,
      coalesce(m.target_fokus_total, 0)::numeric as target_fokus_total,
      coalesce(m.actual_fokus_total, 0)::numeric as actual_fokus_total
    from promotor_scope ps
    left join current_period cp on true
    left join lateral public.get_target_dashboard(ps.promotor_id, cp.period_id) m
      on true
  ),
  counts as (
    select
      (select count(*) from sator_scope)::int as sator_count,
      (select count(*) from promotor_scope)::int as promotor_count,
      (select count(*) from store_scope)::int as store_count
  ),
  daily_totals as (
    select
      coalesce(sum(dr.target_daily_all_type), 0)::numeric as target_sellout,
      coalesce(sum(dr.actual_daily_all_type), 0)::numeric as actual_sellout,
      coalesce(sum(dr.target_daily_focus), 0)::numeric as target_fokus,
      coalesce(sum(dr.actual_daily_focus), 0)::numeric as actual_fokus,
      coalesce(sum(dr.target_weekly_all_type), 0)::numeric as target_sellout_weekly,
      coalesce(sum(dr.actual_weekly_all_type), 0)::numeric as actual_sellout_weekly,
      coalesce(sum(dr.target_weekly_focus), 0)::numeric as target_fokus_weekly,
      coalesce(sum(dr.actual_weekly_focus), 0)::numeric as actual_fokus_weekly,
      max(dr.active_week_number)::int as active_week_number,
      max(dr.active_week_start) as active_week_start,
      max(dr.active_week_end) as active_week_end,
      max(dr.working_days)::int as remaining_workdays
    from daily_rows dr
  ),
  monthly_totals as (
    select
      coalesce(sum(mr.target_omzet), 0)::numeric as target_sellout,
      coalesce(sum(mr.actual_omzet), 0)::numeric as actual_sellout,
      coalesce(sum(mr.target_fokus_total), 0)::numeric as target_fokus,
      coalesce(sum(mr.actual_fokus_total), 0)::numeric as actual_fokus
    from monthly_rows mr
  )
  select jsonb_build_object(
    'period', jsonb_build_object(
      'id', cp.period_id,
      'period_name', cp.period_name,
      'start_date', cp.start_date,
      'end_date', cp.end_date
    ),
    'counts', jsonb_build_object(
      'sators', coalesce(c.sator_count, 0),
      'promotors', coalesce(c.promotor_count, 0),
      'stores', coalesce(c.store_count, 0)
    ),
    'daily', jsonb_build_object(
      'target_sellout', coalesce(dt.target_sellout, 0),
      'actual_sellout', coalesce(dt.actual_sellout, 0),
      'target_fokus', coalesce(dt.target_fokus, 0),
      'actual_fokus', coalesce(dt.actual_fokus, 0)
    ),
    'weekly', jsonb_build_object(
      'week_index', coalesce(dt.active_week_number, 0),
      'week_start', dt.active_week_start,
      'week_end', dt.active_week_end,
      'target_sellout', coalesce(dt.target_sellout_weekly, 0),
      'actual_sellout', coalesce(dt.actual_sellout_weekly, 0),
      'target_fokus', coalesce(dt.target_fokus_weekly, 0),
      'actual_fokus', coalesce(dt.actual_fokus_weekly, 0)
    ),
    'monthly', jsonb_build_object(
      'target_sellout', coalesce(mt.target_sellout, 0),
      'actual_sellout', coalesce(mt.actual_sellout, 0),
      'target_fokus', coalesce(mt.target_fokus, 0),
      'actual_fokus', coalesce(mt.actual_fokus, 0)
    ),
    'remaining_workdays', coalesce(dt.remaining_workdays, 0)
  )
  from current_period cp
  cross join counts c
  left join daily_totals dt on true
  left join monthly_totals mt on true;
$function$;

create or replace function public.get_sator_home_summary(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rollup jsonb := '{}'::jsonb;
  v_promotor_cards jsonb := '{}'::jsonb;
  v_period_id uuid;
  v_start date;
  v_end date;
  v_days int := 0;
  v_day_index int := 0;
  v_store_count int := 0;
  v_promotor_count int := 0;
  v_target_sellout numeric := 0;
  v_target_fokus numeric := 0;
  v_target_sellin numeric := 0;
  v_actual_sellout numeric := 0;
  v_actual_fokus numeric := 0;
  v_actual_sellin numeric := 0;
  v_daily_target_sellout numeric := 0;
  v_daily_target_fokus numeric := 0;
  v_daily_target_sellin numeric := 0;
  v_today_sellout numeric := 0;
  v_today_units int := 0;
  v_today_fokus int := 0;
  v_today_sellin numeric := 0;
  v_attend_count int := 0;
  v_reported_count int := 0;
  v_report_pending int := 0;
  v_week_index int := 1;
  v_week_start date;
  v_week_end date;
  v_week_pct numeric := 25;
  v_week_target_omzet numeric := 0;
  v_week_target_fokus numeric := 0;
  v_week_actual_omzet numeric := 0;
  v_week_actual_fokus numeric := 0;
  v_weekly json := '[]'::json;
  v_agenda json := '[]'::json;
  v_schedule_pending_count int := 0;
  v_permission_pending_count int := 0;
  v_total_approval_pending int := 0;
  v_sellin_pending_count int := 0;
  v_visit_store_name text := null;
  v_target_per_day numeric := 0;
  v_result json;
begin
  v_rollup := coalesce(public.get_sator_dynamic_target_rollup(p_sator_id, current_date), '{}'::jsonb);
  v_promotor_cards := coalesce(public.get_sator_home_promotor_cards(p_sator_id)::jsonb, '{}'::jsonb);

  v_period_id := nullif(v_rollup #>> '{period,id}', '')::uuid;
  v_start := nullif(v_rollup #>> '{period,start_date}', '')::date;
  v_end := nullif(v_rollup #>> '{period,end_date}', '')::date;

  if v_start is null or v_end is null then
    select tp.id, tp.start_date, tp.end_date
    into v_period_id, v_start, v_end
    from target_periods tp
    where current_date between tp.start_date and tp.end_date
      and tp.deleted_at is null
    order by tp.start_date desc, tp.created_at desc
    limit 1;
  end if;

  if v_start is null or v_end is null then
    v_start := date_trunc('month', current_date)::date;
    v_end := (date_trunc('month', current_date) + interval '1 month - 1 day')::date;
  end if;

  v_days := greatest((v_end - v_start) + 1, 1);
  v_day_index := greatest((current_date - v_start) + 1, 1);

  v_store_count := coalesce((v_rollup #>> '{counts,stores}')::int, 0);
  v_promotor_count := coalesce((v_rollup #>> '{counts,promotors}')::int, 0);

  v_target_sellout := coalesce((v_rollup #>> '{monthly,target_sellout}')::numeric, 0);
  v_target_fokus := coalesce((v_rollup #>> '{monthly,target_fokus}')::numeric, 0);
  v_actual_sellout := coalesce((v_rollup #>> '{monthly,actual_sellout}')::numeric, 0);
  v_actual_fokus := coalesce((v_rollup #>> '{monthly,actual_fokus}')::numeric, 0);

  select coalesce(target_sell_in, 0)
  into v_target_sellin
  from user_targets
  where period_id = v_period_id
    and user_id = p_sator_id
  order by updated_at desc
  limit 1;

  select coalesce(sum(total_value), 0)
  into v_actual_sellin
  from sales_sell_in
  where sator_id = p_sator_id
    and transaction_date between v_start and v_end
    and deleted_at is null;

  v_daily_target_sellout := coalesce((v_rollup #>> '{daily,target_sellout}')::numeric, 0);
  v_daily_target_fokus := coalesce((v_rollup #>> '{daily,target_fokus}')::numeric, 0);
  v_daily_target_sellin := case when v_days > 0 then v_target_sellin / v_days else 0 end;

  v_today_sellout := coalesce((v_rollup #>> '{daily,actual_sellout}')::numeric, 0);
  v_today_fokus := coalesce((v_rollup #>> '{daily,actual_fokus}')::numeric, 0)::int;

  select coalesce(sum(total_value), 0)
  into v_today_sellin
  from sales_sell_in
  where sator_id = p_sator_id
    and transaction_date = current_date
    and deleted_at is null;

  select coalesce(sum(s.units_sold), 0)::int
  into v_today_units
  from jsonb_to_recordset(coalesce(v_promotor_cards -> 'daily', '[]'::jsonb)) as s(
    id uuid,
    units_sold int,
    actual_focus_units numeric,
    actual_nominal numeric,
    target_nominal numeric,
    target_focus_units numeric,
    achievement_pct numeric,
    name text,
    nickname text,
    full_name text,
    store_name text,
    underperform boolean
  );

  with promotor_ids as (
    select promotor_id
    from hierarchy_sator_promotor
    where sator_id = p_sator_id and active = true
  )
  select coalesce(count(distinct a.user_id), 0)
  into v_attend_count
  from attendance a
  where a.user_id in (select promotor_id from promotor_ids)
    and a.attendance_date = current_date
    and a.clock_in is not null;

  with promotor_ids as (
    select promotor_id
    from hierarchy_sator_promotor
    where sator_id = p_sator_id and active = true
  )
  select
    coalesce(count(*) filter (where status in ('submitted', 'approved')), 0),
    coalesce(count(*) filter (where status = 'draft'), 0)
  into v_reported_count, v_report_pending
  from schedules
  where promotor_id in (select promotor_id from promotor_ids)
    and to_char(schedule_date, 'YYYY-MM') = to_char(current_date, 'YYYY-MM');

  v_week_index := coalesce((v_rollup #>> '{weekly,week_index}')::int, 1);
  v_week_start := nullif(v_rollup #>> '{weekly,week_start}', '')::date;
  v_week_end := nullif(v_rollup #>> '{weekly,week_end}', '')::date;

  select percentage
  into v_week_pct
  from weekly_targets
  where period_id = v_period_id
    and week_number = v_week_index
  limit 1;

  if v_week_pct is null then
    v_week_pct := 25;
  end if;

  v_week_target_omzet := coalesce((v_rollup #>> '{weekly,target_sellout}')::numeric, 0);
  v_week_target_fokus := coalesce((v_rollup #>> '{weekly,target_fokus}')::numeric, 0);
  v_week_actual_omzet := coalesce((v_rollup #>> '{weekly,actual_sellout}')::numeric, 0);
  v_week_actual_fokus := coalesce((v_rollup #>> '{weekly,actual_fokus}')::numeric, 0);

  with week_sales as (
    select
      (floor((s.transaction_date - v_start) / 7) + 1)::int as week_index,
      coalesce(sum(s.price_at_transaction), 0) as omzet,
      count(*) as units,
      coalesce(sum(case when p.is_focus = true then 1 else 0 end), 0) as fokus
    from sales_sell_out s
    join hierarchy_sator_promotor hsp on hsp.promotor_id = s.promotor_id
    join product_variants pv on pv.id = s.variant_id
    join products p on p.id = pv.product_id
    where hsp.sator_id = p_sator_id
      and hsp.active = true
      and s.transaction_date between v_start and v_end
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
    group by 1
  )
  select coalesce(
    json_agg(
      json_build_object(
        'week', week_index,
        'omzet', omzet,
        'units', units,
        'fokus', fokus
      ) order by week_index
    ),
    '[]'::json
  )
  into v_weekly
  from week_sales;

  select count(*)
  into v_schedule_pending_count
  from public.get_sator_schedule_summary(
    p_sator_id,
    to_char(current_date, 'YYYY-MM')
  ) sch
  where sch.status = 'submitted';

  select coalesce(count(*), 0)
  into v_permission_pending_count
  from public.permission_requests pr
  where pr.sator_approved_by = p_sator_id
    and pr.status = 'pending_sator';

  v_total_approval_pending := coalesce(v_schedule_pending_count, 0)
    + coalesce(v_permission_pending_count, 0);

  select coalesce(count(*), 0)
  into v_sellin_pending_count
  from public.sell_in_orders o
  where o.sator_id = p_sator_id
    and o.order_date = current_date
    and o.status = 'draft';

  select st.store_name
  into v_visit_store_name
  from public.store_visits sv
  join public.stores st on st.id = sv.store_id
  where sv.sator_id = p_sator_id
    and sv.visit_date = current_date
  order by sv.created_at desc
  limit 1;

  v_target_per_day := greatest(v_target_sellout - v_actual_sellout, 0);
  if coalesce((v_rollup ->> 'remaining_workdays')::int, 0) > 0 then
    v_target_per_day := v_target_per_day
      / greatest((v_rollup ->> 'remaining_workdays')::int, 1);
  end if;

  select coalesce(json_agg(item), '[]'::json)
  into v_agenda
  from (
    select json_build_object(
      'type', 'schedule',
      'title', 'Approve Jadwal',
      'sub', coalesce(v_schedule_pending_count, 0)::text || ' pending',
      'status', case when coalesce(v_schedule_pending_count, 0) > 0 then 'pending' else 'ok' end
    ) as item
    union all
    select json_build_object(
      'type', 'permission',
      'title', 'Approve Izin',
      'sub', coalesce(v_permission_pending_count, 0)::text || ' pending',
      'status', case when coalesce(v_permission_pending_count, 0) > 0 then 'pending' else 'ok' end
    )
    union all
    select json_build_object(
      'type', 'visiting',
      'title', 'Visiting',
      'sub', coalesce(v_visit_store_name, 'Tidak ada visiting'),
      'status', case when v_visit_store_name is null then 'idle' else 'done' end
    )
    union all
    select json_build_object(
      'type', 'sellin',
      'title', 'Finalisasi Sell In',
      'sub', coalesce(v_sellin_pending_count, 0)::text || ' order draft',
      'status', case when coalesce(v_sellin_pending_count, 0) > 0 then 'process' else 'ok' end
    )
  ) t;

  v_result := json_build_object(
    'period', json_build_object(
      'id', v_period_id,
      'start_date', v_start,
      'end_date', v_end,
      'days', v_days,
      'day_index', v_day_index
    ),
    'counts', json_build_object(
      'stores', v_store_count,
      'promotors', v_promotor_count
    ),
    'daily', json_build_object(
      'target_sellout', v_daily_target_sellout,
      'actual_sellout', v_today_sellout,
      'target_fokus', v_daily_target_fokus,
      'actual_fokus', v_today_fokus,
      'target_sellin', v_daily_target_sellin,
      'actual_sellin', v_today_sellin,
      'units_sold', v_today_units,
      'attendance_present', v_attend_count,
      'attendance_total', v_promotor_count,
      'reports_done', v_reported_count,
      'reports_pending', v_report_pending
    ),
    'weekly', json_build_object(
      'week_index', v_week_index,
      'week_start', v_week_start,
      'week_end', v_week_end,
      'target_omzet', v_week_target_omzet,
      'actual_omzet', v_week_actual_omzet,
      'target_fokus', v_week_target_fokus,
      'actual_fokus', v_week_actual_fokus,
      'week_pct', v_week_pct,
      'progress', v_weekly
    ),
    'monthly', json_build_object(
      'target_omzet', v_target_sellout,
      'actual_omzet', v_actual_sellout,
      'target_fokus', v_target_fokus,
      'actual_fokus', v_actual_fokus,
      'target_sellin', v_target_sellin,
      'actual_sellin', v_actual_sellin,
      'target_per_day', v_target_per_day
    ),
    'daily_promotors', coalesce(v_promotor_cards -> 'daily', '[]'::jsonb),
    'weekly_promotors', coalesce(v_promotor_cards -> 'weekly', '[]'::jsonb),
    'agenda', v_agenda
  );

  return v_result;
end;
$function$;

create or replace function public.get_sator_home_weekly_snapshots(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_period_id uuid;
  v_start date;
  v_end date;
  v_active_week_number integer := 0;
  v_weekly_snapshots jsonb := '[]'::jsonb;
  v_week record;
  v_week_start date;
  v_week_end date;
  v_working_days integer := 0;
  v_elapsed_working_days integer := 0;
  v_summary jsonb := '{}'::jsonb;
  v_week_promotors jsonb := '[]'::jsonb;
begin
  if p_sator_id is null then
    raise exception 'p_sator_id is required';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is null then
    return jsonb_build_object(
      'active_week_number', 0,
      'weekly_snapshots', '[]'::jsonb
    );
  end if;

  select coalesce(wt.week_number, 0)
  into v_active_week_number
  from public.weekly_targets wt
  where wt.period_id = v_period_id
    and extract(day from p_date)::int between wt.start_day and wt.end_day
  order by wt.week_number
  limit 1;

  if v_active_week_number = 0 then
    v_active_week_number := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);
  end if;

  for v_week in
    select
      gs.week_number,
      coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
      coalesce(
        wt.end_day,
        case
          when gs.week_number < 4 then gs.week_number * 7
          else extract(day from v_end)::int
        end
      ) as end_day,
      coalesce(wt.percentage, 25) as percentage
    from generate_series(1, 4) as gs(week_number)
    left join public.weekly_targets wt
      on wt.period_id = v_period_id
     and wt.week_number = gs.week_number
    order by gs.week_number
  loop
    v_week_start := greatest(v_start, v_start + (v_week.start_day - 1));
    v_week_end := least(v_end, v_start + (v_week.end_day - 1));

    select count(*)::int
    into v_working_days
    from generate_series(v_week_start, v_week_end, interval '1 day') as day_ref
    where extract(isodow from day_ref)::int < 7;

    if p_date < v_week_start then
      v_elapsed_working_days := 0;
    else
      select count(*)::int
      into v_elapsed_working_days
      from generate_series(
        v_week_start,
        least(v_week_end, p_date),
        interval '1 day'
      ) as day_ref
      where extract(isodow from day_ref)::int < 7;
    end if;

    with promotor_scope as (
      select
        u.id as promotor_id,
        coalesce(u.full_name, 'Promotor') as full_name,
        coalesce(ps.store_name, '-') as store_name
      from public.hierarchy_sator_promotor hsp
      join public.users u on u.id = hsp.promotor_id
      left join lateral (
        select st.store_name
        from public.assignments_promotor_store aps
        join public.stores st on st.id = aps.store_id
        where aps.promotor_id = u.id
          and aps.active = true
        order by aps.created_at desc nulls last
        limit 1
      ) ps on true
      where hsp.sator_id = p_sator_id
        and hsp.active = true
        and u.deleted_at is null
    ),
    promotor_week as (
      select
        ps.promotor_id,
        ps.full_name,
        ps.store_name,
        coalesce((pw ->> 'target_weekly_all_type')::numeric, 0) as target_nominal,
        coalesce((pw ->> 'actual_weekly_all_type')::numeric, 0) as actual_nominal,
        coalesce((pw ->> 'target_weekly_focus')::numeric, 0) as target_focus_units,
        coalesce((pw ->> 'actual_weekly_focus')::numeric, 0) as actual_focus_units,
        coalesce((pw ->> 'achievement_weekly_all_type_pct')::numeric, 0) as achievement_pct
      from promotor_scope ps
      left join lateral public.get_promotor_week_snapshot(
        ps.promotor_id,
        v_period_id,
        v_week.week_number,
        p_date
      ) pw on true
    )
    select jsonb_build_object(
      'week_index', v_week.week_number,
      'week_start', v_week_start,
      'week_end', v_week_end,
      'week_pct', v_week.percentage,
      'target_omzet', coalesce(sum(pw.target_nominal), 0),
      'actual_omzet', coalesce(sum(pw.actual_nominal), 0),
      'target_fokus', coalesce(sum(pw.target_focus_units), 0),
      'actual_fokus', coalesce(sum(pw.actual_focus_units), 0),
      'reports_pending', 0
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'promotor_id', pw.promotor_id,
          'name', pw.full_name,
          'store_name', pw.store_name,
          'target_nominal', pw.target_nominal,
          'actual_nominal', pw.actual_nominal,
          'target_focus_units', pw.target_focus_units,
          'actual_focus_units', pw.actual_focus_units,
          'achievement_pct', pw.achievement_pct,
          'underperform', pw.achievement_pct > 0 and pw.achievement_pct < 60
        )
        order by pw.actual_nominal desc, pw.full_name
      ),
      '[]'::jsonb
    )
    into v_summary, v_week_promotors
    from promotor_week pw;

    v_weekly_snapshots := v_weekly_snapshots || jsonb_build_array(
      jsonb_build_object(
        'week_number', v_week.week_number,
        'start_date', v_week_start,
        'end_date', v_week_end,
        'percentage_of_total', v_week.percentage,
        'is_active', v_week.week_number = v_active_week_number,
        'is_future', v_week_start > p_date,
        'status_label', case
          when v_week_start > p_date then 'Belum berjalan'
          when v_week.week_number = v_active_week_number then 'Minggu aktif'
          else 'Riwayat minggu'
        end,
        'working_days', v_working_days,
        'elapsed_working_days', v_elapsed_working_days,
        'summary', coalesce(v_summary, '{}'::jsonb),
        'promotors', coalesce(v_week_promotors, '[]'::jsonb)
      )
    );
  end loop;

  return jsonb_build_object(
    'active_week_number', v_active_week_number,
    'weekly_snapshots', coalesce(v_weekly_snapshots, '[]'::jsonb)
  );
end;
$$;

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
  v_base jsonb := '{}'::jsonb;
  v_rollup jsonb := '{}'::jsonb;
  v_vast_daily jsonb := '{}'::jsonb;
  v_vast_weekly jsonb := '{}'::jsonb;
  v_vast_monthly jsonb := '{}'::jsonb;
  v_enriched_sator_cards jsonb := '[]'::jsonb;
  v_month_key date := date_trunc('month', p_date)::date;
  v_month_start date := date_trunc('month', p_date)::date;
  v_period_id uuid;
  v_period_start date;
  v_period_end date;
  v_week_number integer := 1;
  v_week_start_day integer := 1;
  v_week_end_day integer := 7;
  v_week_start date;
  v_week_end date;
  v_active_week_percentage numeric := 25;
  v_target_vast numeric := 0;
begin
  v_base := coalesce(
    public.get_spv_home_snapshot_base(p_spv_id, p_date),
    '{}'::jsonb
  );
  v_rollup := coalesce(public.get_spv_dynamic_target_rollup(p_spv_id, p_date), '{}'::jsonb);

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_period_start, v_period_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is not null then
    v_week_number := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);

    select
      coalesce(wt.start_day, ((v_week_number - 1) * 7) + 1),
      coalesce(
        wt.end_day,
        case
          when v_week_number < 4 then v_week_number * 7
          else extract(day from v_period_end)::int
        end
      ),
      coalesce(wt.percentage, 25)
    into v_week_start_day, v_week_end_day, v_active_week_percentage
    from public.weekly_targets wt
    where wt.period_id = v_period_id
      and wt.week_number = v_week_number;

    v_week_start_day := coalesce(v_week_start_day, ((v_week_number - 1) * 7) + 1);
    v_week_end_day := coalesce(
      v_week_end_day,
      case
        when v_week_number < 4 then v_week_number * 7
        else extract(day from v_period_end)::int
      end
    );
    v_active_week_percentage := coalesce(v_active_week_percentage, 25);

    v_week_start := greatest(v_period_start, v_period_start + (v_week_start_day - 1));
    v_week_end := least(v_period_end, v_period_start + (v_week_end_day - 1));

    select coalesce(ut.target_vast, 0)
    into v_target_vast
    from public.user_targets ut
    where ut.user_id = p_spv_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc nulls last
    limit 1;
  else
    v_week_start := v_month_start;
    v_week_end := p_date;
  end if;

  select to_jsonb(vd.*)
  into v_vast_daily
  from public.vast_agg_daily_spv vd
  where vd.spv_id = p_spv_id
    and vd.metric_date = p_date
  limit 1;

  with weekly_rollup as (
    select
      round(coalesce(v_target_vast, 0) * coalesce(v_active_week_percentage, 25) / 100.0)::int as target_submissions,
      coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
      coalesce(sum(vd.total_acc), 0)::int as total_acc,
      coalesce(sum(vd.total_pending), 0)::int as total_pending,
      coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
      coalesce(sum(vd.total_reject), 0)::int as total_reject,
      coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
      coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
      coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts,
      coalesce(max(vd.promotor_with_input), 0)::int as promotor_with_input
    from public.vast_agg_daily_spv vd
    where vd.spv_id = p_spv_id
      and vd.metric_date between coalesce(v_week_start, v_month_start) and least(coalesce(v_week_end, p_date), p_date)
  )
  select jsonb_build_object(
    'week_start_date', coalesce(v_week_start, v_month_start),
    'week_end_date', least(coalesce(v_week_end, p_date), p_date),
    'target_submissions', wr.target_submissions,
    'total_submissions', wr.total_submissions,
    'total_acc', wr.total_acc,
    'total_pending', wr.total_pending,
    'total_active_pending', wr.total_active_pending,
    'total_reject', wr.total_reject,
    'total_closed_direct', wr.total_closed_direct,
    'total_closed_follow_up', wr.total_closed_follow_up,
    'total_duplicate_alerts', wr.total_duplicate_alerts,
    'promotor_with_input', wr.promotor_with_input,
    'achievement_pct', case
      when wr.target_submissions > 0 then round((wr.total_submissions::numeric / wr.target_submissions::numeric) * 100, 2)
      else 0
    end
  )
  into v_vast_weekly
  from weekly_rollup wr;

  select to_jsonb(vm.*)
  into v_vast_monthly
  from public.vast_agg_monthly_spv vm
  where vm.spv_id = p_spv_id
    and vm.month_key = v_month_key
  limit 1;

  if coalesce(v_vast_monthly, '{}'::jsonb) = '{}'::jsonb then
    with monthly_rollup as (
      select
        round(coalesce(v_target_vast, 0))::int as target_submissions,
        coalesce(sum(vd.total_submissions), 0)::int as total_submissions,
        coalesce(sum(vd.total_acc), 0)::int as total_acc,
        coalesce(sum(vd.total_pending), 0)::int as total_pending,
        coalesce(sum(vd.total_active_pending), 0)::int as total_active_pending,
        coalesce(sum(vd.total_reject), 0)::int as total_reject,
        coalesce(sum(vd.total_closed_direct), 0)::int as total_closed_direct,
        coalesce(sum(vd.total_closed_follow_up), 0)::int as total_closed_follow_up,
        coalesce(sum(vd.total_duplicate_alerts), 0)::int as total_duplicate_alerts,
        coalesce(max(vd.promotor_with_input), 0)::int as promotor_with_input
      from public.vast_agg_daily_spv vd
      where vd.spv_id = p_spv_id
        and vd.metric_date between v_month_start and p_date
    )
    select jsonb_build_object(
      'month_key', v_month_key,
      'target_submissions', mr.target_submissions,
      'total_submissions', mr.total_submissions,
      'total_acc', mr.total_acc,
      'total_pending', mr.total_pending,
      'total_active_pending', mr.total_active_pending,
      'total_reject', mr.total_reject,
      'total_closed_direct', mr.total_closed_direct,
      'total_closed_follow_up', mr.total_closed_follow_up,
      'total_duplicate_alerts', mr.total_duplicate_alerts,
      'promotor_with_input', mr.promotor_with_input,
      'achievement_pct', case
        when mr.target_submissions > 0 then round((mr.total_submissions::numeric / mr.target_submissions::numeric) * 100, 2)
        else 0
      end
    )
    into v_vast_monthly
    from monthly_rollup mr;
  end if;

  with base_cards as (
    select
      card,
      ordinality,
      nullif(card ->> 'sator_id', '')::uuid as sator_id
    from jsonb_array_elements(coalesce(v_base -> 'sator_cards', '[]'::jsonb))
      with ordinality as t(card, ordinality)
  ),
  dynamic_rollup as (
    select
      bc.sator_id,
      public.get_sator_dynamic_target_rollup(bc.sator_id, p_date) as rollup
    from base_cards bc
  ),
  sellin_targets as (
    select
      bc.sator_id,
      coalesce(ut.target_sell_in, 0)::numeric as target_sell_in_monthly
    from base_cards bc
    left join public.user_targets ut
      on ut.user_id = bc.sator_id
     and ut.period_id = v_period_id
  ),
  sellin_actuals as (
    select
      bc.sator_id,
      coalesce(sum(case when o.order_date = p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_daily,
      coalesce(sum(case when o.order_date between coalesce(v_week_start, v_month_start) and p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_weekly,
      coalesce(sum(case when o.order_date between v_month_start and p_date then o.total_value else 0 end), 0)::numeric as actual_sell_in_monthly
    from base_cards bc
    left join public.sell_in_orders o
      on o.sator_id = bc.sator_id
     and o.status = 'finalized'
     and o.order_date between v_month_start and p_date
    group by bc.sator_id
  ),
  merged as (
    select
      bc.ordinality,
      bc.card ||
        jsonb_build_object(
          'target_sell_out_daily', coalesce((dr.rollup #>> '{daily,target_sellout}')::numeric, 0),
          'target_sell_out_weekly', coalesce((dr.rollup #>> '{weekly,target_sellout}')::numeric, 0),
          'target_sell_out_monthly', coalesce((dr.rollup #>> '{monthly,target_sellout}')::numeric, 0),
          'actual_sell_out_daily', coalesce((dr.rollup #>> '{daily,actual_sellout}')::numeric, 0),
          'actual_sell_out_weekly', coalesce((dr.rollup #>> '{weekly,actual_sellout}')::numeric, 0),
          'actual_sell_out_monthly', coalesce((dr.rollup #>> '{monthly,actual_sellout}')::numeric, 0),
          'target_focus_daily', coalesce((dr.rollup #>> '{daily,target_fokus}')::numeric, 0),
          'target_focus_weekly', coalesce((dr.rollup #>> '{weekly,target_fokus}')::numeric, 0),
          'target_focus_monthly', coalesce((dr.rollup #>> '{monthly,target_fokus}')::numeric, 0),
          'actual_focus_daily', coalesce((dr.rollup #>> '{daily,actual_fokus}')::numeric, 0),
          'actual_focus_weekly', coalesce((dr.rollup #>> '{weekly,actual_fokus}')::numeric, 0),
          'actual_focus_monthly', coalesce((dr.rollup #>> '{monthly,actual_fokus}')::numeric, 0),
          'achievement_pct_monthly', case
            when coalesce((dr.rollup #>> '{monthly,target_sellout}')::numeric, 0) > 0
              then round(
                (
                  coalesce((dr.rollup #>> '{monthly,actual_sellout}')::numeric, 0)
                  / (dr.rollup #>> '{monthly,target_sellout}')::numeric
                ) * 100,
                0
              )
            else 0
          end,
          'target_sell_in_daily', round((coalesce(st.target_sell_in_monthly, 0) * v_active_week_percentage / 100.0) / 6.0),
          'target_sell_in_weekly', round(coalesce(st.target_sell_in_monthly, 0) * v_active_week_percentage / 100.0),
          'target_sell_in_monthly', round(coalesce(st.target_sell_in_monthly, 0)),
          'actual_sell_in_daily', round(coalesce(sa.actual_sell_in_daily, 0)),
          'actual_sell_in_weekly', round(coalesce(sa.actual_sell_in_weekly, 0)),
          'actual_sell_in_monthly', round(coalesce(sa.actual_sell_in_monthly, 0))
        ) as card
    from base_cards bc
    left join dynamic_rollup dr on dr.sator_id = bc.sator_id
    left join sellin_targets st on st.sator_id = bc.sator_id
    left join sellin_actuals sa on sa.sator_id = bc.sator_id
  )
  select coalesce(jsonb_agg(card order by ordinality), '[]'::jsonb)
  into v_enriched_sator_cards
  from merged;

  return v_base || jsonb_build_object(
    'team_target_data', jsonb_build_object(
      'target_sell_out_monthly', coalesce((v_rollup #>> '{monthly,target_sellout}')::numeric, 0),
      'target_sell_out_weekly', coalesce((v_rollup #>> '{weekly,target_sellout}')::numeric, 0),
      'target_sell_out_daily', coalesce((v_rollup #>> '{daily,target_sellout}')::numeric, 0),
      'target_focus_monthly', coalesce((v_rollup #>> '{monthly,target_fokus}')::numeric, 0),
      'target_focus_weekly', coalesce((v_rollup #>> '{weekly,target_fokus}')::numeric, 0),
      'target_focus_daily', coalesce((v_rollup #>> '{daily,target_fokus}')::numeric, 0),
      'active_week_number', coalesce((v_rollup #>> '{weekly,week_index}')::int, 0),
      'active_week_percentage', v_active_week_percentage,
      'working_days', coalesce((v_rollup ->> 'remaining_workdays')::int, 0)
    ),
    'sator_cards', coalesce(v_enriched_sator_cards, '[]'::jsonb),
    'vast_daily', coalesce(v_vast_daily, '{}'::jsonb),
    'vast_weekly', coalesce(v_vast_weekly, '{}'::jsonb),
    'vast_monthly', coalesce(v_vast_monthly, '{}'::jsonb)
  );
end;
$function$;

create or replace function public.get_spv_home_weekly_snapshots(
  p_spv_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_period_id uuid;
  v_start date;
  v_end date;
  v_active_week_number integer := 0;
  v_weekly_snapshots jsonb := '[]'::jsonb;
  v_week record;
  v_week_start date;
  v_week_end date;
  v_working_days integer := 0;
  v_elapsed_working_days integer := 0;
  v_summary jsonb := '{}'::jsonb;
  v_sator_cards jsonb := '[]'::jsonb;
begin
  if p_spv_id is null then
    raise exception 'p_spv_id is required';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is null then
    return jsonb_build_object(
      'active_week_number', 0,
      'weekly_snapshots', '[]'::jsonb
    );
  end if;

  select coalesce(wt.week_number, 0)
  into v_active_week_number
  from public.weekly_targets wt
  where wt.period_id = v_period_id
    and extract(day from p_date)::int between wt.start_day and wt.end_day
  order by wt.week_number
  limit 1;

  if v_active_week_number = 0 then
    v_active_week_number := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);
  end if;

  for v_week in
    select
      gs.week_number,
      coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
      coalesce(
        wt.end_day,
        case
          when gs.week_number < 4 then gs.week_number * 7
          else extract(day from v_end)::int
        end
      ) as end_day,
      coalesce(wt.percentage, 25) as percentage
    from generate_series(1, 4) as gs(week_number)
    left join public.weekly_targets wt
      on wt.period_id = v_period_id
     and wt.week_number = gs.week_number
    order by gs.week_number
  loop
    v_week_start := greatest(v_start, v_start + (v_week.start_day - 1));
    v_week_end := least(v_end, v_start + (v_week.end_day - 1));

    select count(*)::int
    into v_working_days
    from generate_series(v_week_start, v_week_end, interval '1 day') as day_ref
    where extract(isodow from day_ref)::int < 7;

    if p_date < v_week_start then
      v_elapsed_working_days := 0;
    else
      select count(*)::int
      into v_elapsed_working_days
      from generate_series(
        v_week_start,
        least(v_week_end, p_date),
        interval '1 day'
      ) as day_ref
      where extract(isodow from day_ref)::int < 7;
    end if;

    with sator_scope as (
      select
        u.id as sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name,
        coalesce(u.area, '-') as sator_area
      from public.hierarchy_spv_sator hss
      join public.users u on u.id = hss.sator_id
      where hss.spv_id = p_spv_id
        and hss.active = true
        and u.deleted_at is null
    ),
    promotor_scope as (
      select
        ss.sator_id,
        ss.sator_name,
        ss.sator_area,
        u.id as promotor_id,
        coalesce(u.full_name, 'Promotor') as promotor_name
      from sator_scope ss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = ss.sator_id
       and hsp.active = true
      join public.users u on u.id = hsp.promotor_id
      where u.deleted_at is null
    ),
    promotor_week as (
      select
        ps.sator_id,
        ps.sator_name,
        ps.sator_area,
        ps.promotor_id,
        ps.promotor_name,
        coalesce((pw ->> 'target_weekly_all_type')::numeric, 0) as target_weekly_all_type,
        coalesce((pw ->> 'actual_weekly_all_type')::numeric, 0) as actual_weekly_all_type,
        coalesce((pw ->> 'target_weekly_focus')::numeric, 0) as target_weekly_focus,
        coalesce((pw ->> 'actual_weekly_focus')::numeric, 0) as actual_weekly_focus
      from promotor_scope ps
      left join lateral public.get_promotor_week_snapshot(
        ps.promotor_id,
        v_period_id,
        v_week.week_number,
        p_date
      ) pw on true
    ),
    sator_rollup as (
      select
        pw.sator_id,
        max(pw.sator_name) as sator_name,
        max(pw.sator_area) as sator_area,
        count(distinct pw.promotor_id)::int as promotor_count,
        coalesce(sum(pw.target_weekly_all_type), 0)::numeric as target_sell_out_weekly,
        coalesce(sum(pw.actual_weekly_all_type), 0)::numeric as actual_sell_out_weekly,
        coalesce(sum(pw.target_weekly_focus), 0)::numeric as target_focus_weekly,
        coalesce(sum(pw.actual_weekly_focus), 0)::numeric as actual_focus_weekly
      from promotor_week pw
      group by pw.sator_id
    ),
    top_promotors as (
      select
        ranked.sator_id,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'name', ranked.promotor_name,
              'units', ranked.actual_units
            )
            order by ranked.actual_units desc, ranked.promotor_name
          ),
          '[]'::jsonb
        ) as rows
      from (
        select
          pw.sator_id,
          pw.promotor_name,
          coalesce(pw.actual_weekly_focus, 0)::int as actual_units,
          row_number() over (
            partition by pw.sator_id
            order by coalesce(pw.actual_weekly_all_type, 0) desc, pw.promotor_name
          ) as rn
        from promotor_week pw
      ) ranked
      where ranked.rn <= 3
      group by ranked.sator_id
    )
    select jsonb_build_object(
      'target_sell_out_weekly', coalesce(sum(sr.target_sell_out_weekly), 0),
      'target_focus_weekly', coalesce(sum(sr.target_focus_weekly), 0),
      'actual_sell_out_weekly', coalesce(sum(sr.actual_sell_out_weekly), 0),
      'actual_focus_weekly', coalesce(sum(sr.actual_focus_weekly), 0)
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sator_id', sr.sator_id,
          'sator_name', sr.sator_name,
          'sator_area', sr.sator_area,
          'promotor_count', sr.promotor_count,
          'target_sell_out_weekly', sr.target_sell_out_weekly,
          'actual_sell_out_weekly', sr.actual_sell_out_weekly,
          'target_focus_weekly', sr.target_focus_weekly,
          'actual_focus_weekly', sr.actual_focus_weekly,
          'top_promotors', coalesce(tp.rows, '[]'::jsonb)
        )
        order by sr.actual_sell_out_weekly desc, sr.sator_name
      ),
      '[]'::jsonb
    )
    into v_summary, v_sator_cards
    from sator_rollup sr
    left join top_promotors tp on tp.sator_id = sr.sator_id;

    v_weekly_snapshots := v_weekly_snapshots || jsonb_build_array(
      jsonb_build_object(
        'week_number', v_week.week_number,
        'start_date', v_week_start,
        'end_date', v_week_end,
        'percentage_of_total', v_week.percentage,
        'is_active', v_week.week_number = v_active_week_number,
        'is_future', v_week_start > p_date,
        'status_label', case
          when v_week_start > p_date then 'Belum berjalan'
          when v_week.week_number = v_active_week_number then 'Minggu aktif'
          else 'Riwayat minggu'
        end,
        'working_days', v_working_days,
        'elapsed_working_days', v_elapsed_working_days,
        'summary', coalesce(v_summary, '{}'::jsonb),
        'sator_cards', coalesce(v_sator_cards, '[]'::jsonb)
      )
    );
  end loop;

  return jsonb_build_object(
    'active_week_number', v_active_week_number,
    'weekly_snapshots', coalesce(v_weekly_snapshots, '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_sator_visiting_briefing(
  p_sator_id uuid,
  p_store_id uuid,
  p_date date default current_date
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_result json;
begin
  with active_promotors as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      u.full_name,
      coalesce(u.nickname, u.full_name) as display_name
    from public.assignments_promotor_store aps
    join public.users u on u.id = aps.promotor_id
    where aps.store_id = p_store_id
      and aps.active = true
      and u.status = 'active'
    order by aps.promotor_id, aps.created_at desc nulls last
  ),
  home_snapshot_by_promotor as (
    select
      ap.promotor_id,
      coalesce(public.get_promotor_home_snapshot(ap.promotor_id, p_date), '{}'::jsonb) as snapshot
    from active_promotors ap
  ),
  target_summary as (
    select
      coalesce(sum(coalesce((hs.snapshot -> 'daily_target' ->> 'target_daily_all_type')::numeric, 0)), 0)::numeric as daily_target_omzet,
      coalesce(sum(coalesce((hs.snapshot -> 'daily_target' ->> 'target_daily_focus')::numeric, 0)), 0)::numeric as daily_target_focus,
      coalesce(sum(coalesce((hs.snapshot -> 'monthly_target' ->> 'target_omzet')::numeric, 0)), 0)::numeric as monthly_target_omzet,
      coalesce(sum(coalesce((hs.snapshot -> 'monthly_target' ->> 'target_fokus_total')::numeric, 0)), 0)::numeric as monthly_target_focus,
      coalesce(sum(ut.target_vast), 0)::int as monthly_target_vast
    from active_promotors ap
    left join home_snapshot_by_promotor hs on hs.promotor_id = ap.promotor_id
    left join lateral (
      select ut.target_vast
      from public.user_targets ut
      where ut.user_id = ap.promotor_id
      order by ut.updated_at desc
      limit 1
    ) ut on true
  ),
  sales_today as (
    select
      coalesce(sum(s.price_at_transaction), 0)::int as omzet,
      count(*)::int as all_type_units,
      count(*) filter (
        where coalesce(p.is_focus, false) or coalesce(p.is_fokus, false)
      )::int as focus_units
    from public.sales_sell_out s
    join public.product_variants pv on pv.id = s.variant_id
    join public.products p on p.id = pv.product_id
    where s.store_id = p_store_id
      and s.transaction_date = p_date
      and s.deleted_at is null
  ),
  activity_by_promotor as (
    select
      ap.promotor_id,
      ap.display_name,
      hs.snapshot as home_snapshot,
      exists(
        select 1
        from public.attendance a
        where a.user_id = ap.promotor_id
          and a.attendance_date = p_date
          and a.clock_in is not null
      ) as clock_in,
      (
        select count(*)::int
        from public.sales_sell_out s
        where s.promotor_id = ap.promotor_id
          and s.store_id = p_store_id
          and s.transaction_date = p_date
          and s.deleted_at is null
      ) as sales_count,
      (
        select coalesce(sum(s.price_at_transaction), 0)::int
        from public.sales_sell_out s
        where s.promotor_id = ap.promotor_id
          and s.store_id = p_store_id
          and s.transaction_date = p_date
          and s.deleted_at is null
      ) as daily_omzet,
      (
        select count(*)::int
        from public.sales_sell_out s
        join public.product_variants pv on pv.id = s.variant_id
        join public.products p on p.id = pv.product_id
        where s.promotor_id = ap.promotor_id
          and s.store_id = p_store_id
          and s.transaction_date = p_date
          and s.deleted_at is null
          and (coalesce(p.is_focus, false) or coalesce(p.is_fokus, false))
      ) as focus_units,
      (
        select count(*)::int
        from public.stock_movement_log sml
        where sml.moved_by = ap.promotor_id
          and coalesce(sml.to_store_id, sml.from_store_id) = p_store_id
          and (sml.moved_at at time zone 'Asia/Makassar')::date = p_date
      ) as stock_count,
      exists(
        select 1
        from public.allbrand_reports ar
        where ar.promotor_id = ap.promotor_id
          and ar.store_id = p_store_id
          and ar.report_date = p_date
      ) as allbrand_sent,
      coalesce((hs.snapshot -> 'daily_target' ->> 'target_daily_all_type')::numeric, 0) as target_daily_all_type,
      coalesce((hs.snapshot -> 'daily_target' ->> 'actual_daily_all_type')::numeric, 0) as actual_daily_all_type,
      coalesce((hs.snapshot -> 'daily_target' ->> 'achievement_daily_all_type_pct')::numeric, 0) as achievement_daily_all_type_pct,
      coalesce((hs.snapshot -> 'daily_target' ->> 'target_daily_focus')::numeric, 0) as target_daily_focus,
      coalesce((hs.snapshot -> 'daily_target' ->> 'actual_daily_focus')::numeric, 0) as actual_daily_focus,
      coalesce((hs.snapshot -> 'daily_target' ->> 'achievement_daily_focus_pct')::numeric, 0) as achievement_daily_focus_pct,
      coalesce((hs.snapshot -> 'daily_target' ->> 'target_weekly_all_type')::numeric, 0) as target_weekly_all_type,
      coalesce((hs.snapshot -> 'daily_target' ->> 'actual_weekly_all_type')::numeric, 0) as actual_weekly_all_type,
      coalesce((hs.snapshot -> 'daily_target' ->> 'achievement_weekly_all_type_pct')::numeric, 0) as achievement_weekly_all_type_pct,
      coalesce((hs.snapshot -> 'daily_target' ->> 'target_weekly_focus')::numeric, 0) as target_weekly_focus,
      coalesce((hs.snapshot -> 'daily_target' ->> 'actual_weekly_focus')::numeric, 0) as actual_weekly_focus,
      coalesce((hs.snapshot -> 'daily_target' ->> 'achievement_weekly_focus_pct')::numeric, 0) as achievement_weekly_focus_pct,
      coalesce((hs.snapshot -> 'monthly_target' ->> 'target_omzet')::numeric, 0) as monthly_target_omzet,
      coalesce((hs.snapshot -> 'monthly_target' ->> 'actual_omzet')::numeric, 0) as monthly_actual_omzet,
      coalesce((hs.snapshot -> 'monthly_target' ->> 'achievement_omzet_pct')::numeric, 0) as monthly_achievement_omzet_pct,
      coalesce((hs.snapshot -> 'monthly_target' ->> 'target_fokus_total')::numeric, 0) as monthly_target_focus,
      coalesce((hs.snapshot -> 'monthly_target' ->> 'actual_fokus_total')::numeric, 0) as monthly_actual_focus,
      coalesce((hs.snapshot -> 'monthly_target' ->> 'achievement_fokus_pct')::numeric, 0) as monthly_achievement_focus_pct,
      coalesce((hs.snapshot ->> 'active_week_number')::int, (hs.snapshot -> 'daily_target' ->> 'active_week_number')::int, 0) as active_week_number,
      nullif(hs.snapshot -> 'daily_target' ->> 'active_week_start', '')::date as active_week_start,
      nullif(hs.snapshot -> 'daily_target' ->> 'active_week_end', '')::date as active_week_end,
      nullif(hs.snapshot -> 'monthly_target' ->> 'start_date', '')::date as period_start,
      nullif(hs.snapshot -> 'monthly_target' ->> 'end_date', '')::date as period_end,
      coalesce(
        (
          select weekly_item
          from jsonb_array_elements(coalesce(hs.snapshot -> 'weekly_snapshots', '[]'::jsonb)) weekly_item
          where coalesce((weekly_item ->> 'is_active')::boolean, false) = true
             or coalesce((weekly_item ->> 'week_number')::int, 0) = coalesce((hs.snapshot ->> 'active_week_number')::int, 0)
          order by coalesce((weekly_item ->> 'is_active')::boolean, false) desc,
                   coalesce((weekly_item ->> 'week_number')::int, 0)
          limit 1
        ),
        '{}'::jsonb
      ) as active_week_snapshot,
      coalesce(hs.snapshot -> 'daily_special_rows', '[]'::jsonb) as daily_special_rows,
      coalesce(hs.snapshot -> 'weekly_special_rows', '[]'::jsonb) as weekly_special_rows,
      coalesce(hs.snapshot -> 'monthly_special_rows', '[]'::jsonb) as monthly_special_rows,
      coalesce((
        select ut.target_vast
        from public.user_targets ut
        where ut.user_id = ap.promotor_id
        order by ut.updated_at desc
        limit 1
      ), 0)::int as vast_target,
      coalesce((
        select v.total_submissions
        from public.vast_agg_monthly_promotor v
        where v.promotor_id = ap.promotor_id
          and v.store_id = p_store_id
          and v.month_key = date_trunc('month', p_date)::date
        limit 1
      ), 0)::int as vast_month_submissions,
      coalesce((
        select v.total_acc
        from public.vast_agg_monthly_promotor v
        where v.promotor_id = ap.promotor_id
          and v.store_id = p_store_id
          and v.month_key = date_trunc('month', p_date)::date
        limit 1
      ), 0)::int as vast_month_acc,
      coalesce((
        select v.total_active_pending
        from public.vast_agg_monthly_promotor v
        where v.promotor_id = ap.promotor_id
          and v.store_id = p_store_id
          and v.month_key = date_trunc('month', p_date)::date
        limit 1
      ), 0)::int as vast_month_pending,
      coalesce((
        select v.achievement_pct
        from public.vast_agg_monthly_promotor v
        where v.promotor_id = ap.promotor_id
          and v.store_id = p_store_id
          and v.month_key = date_trunc('month', p_date)::date
        limit 1
      ), 0)::numeric as vast_month_achievement_pct
    from active_promotors ap
    left join home_snapshot_by_promotor hs on hs.promotor_id = ap.promotor_id
  ),
  latest_allbrand_by_promotor as (
    select distinct on (ar.promotor_id)
      ar.promotor_id,
      ar.report_date,
      coalesce(ar.daily_total_units, 0)::int as competitor_units,
      coalesce(ar.cumulative_total_units, 0)::int as cumulative_units,
      coalesce((ar.vivo_auto_data ->> 'total')::int, 0) as vivo_units,
      case
        when coalesce(ar.daily_total_units, 0) + coalesce((ar.vivo_auto_data ->> 'total')::int, 0) > 0
        then round(
          (
            coalesce((ar.vivo_auto_data ->> 'total')::numeric, 0) /
            (coalesce(ar.daily_total_units, 0)::numeric + coalesce((ar.vivo_auto_data ->> 'total')::numeric, 0))
          ) * 100,
          1
        )
        else 0
      end as vivo_market_share
    from public.allbrand_reports ar
    where ar.store_id = p_store_id
      and ar.promotor_id in (select promotor_id from active_promotors)
      and ar.report_date <= p_date
    order by ar.promotor_id, ar.report_date desc, ar.updated_at desc nulls last, ar.created_at desc nulls last
  ),
  vast_history_by_promotor as (
    select
      v.promotor_id,
      json_agg(
        json_build_object(
          'month_key', v.month_key,
          'target_submissions', coalesce(v.target_submissions, 0)::int,
          'total_submissions', coalesce(v.total_submissions, 0)::int,
          'total_acc', coalesce(v.total_acc, 0)::int,
          'total_active_pending', coalesce(v.total_active_pending, 0)::int,
          'achievement_pct', coalesce(v.achievement_pct, 0)
        )
        order by v.month_key desc
      ) as rows
    from public.vast_agg_monthly_promotor v
    where v.store_id = p_store_id
      and v.promotor_id in (select promotor_id from active_promotors)
      and v.month_key <= date_trunc('month', p_date)::date
    group by v.promotor_id
  ),
  activity_summary as (
    select
      count(*)::int as promotor_count,
      count(*) filter (where clock_in)::int as present_count,
      count(*) filter (
        where not clock_in or (sales_count = 0 and stock_count = 0)
      )::int as low_activity_count,
      coalesce(
        json_agg(
          json_build_object(
            'promotor_id', a.promotor_id,
            'promotor_name', a.display_name,
            'clock_in', a.clock_in,
            'sales_count', a.sales_count,
            'stock_count', a.stock_count,
            'allbrand_sent', a.allbrand_sent,
            'daily_omzet', a.daily_omzet,
            'daily_target', a.target_daily_all_type,
            'focus_units', a.focus_units,
            'focus_target', a.target_daily_focus,
            'monthly_target_omzet', a.monthly_target_omzet,
            'vast_target', a.vast_target,
            'vast_month_submissions', a.vast_month_submissions,
            'vast_month_acc', a.vast_month_acc,
            'vast_month_pending', a.vast_month_pending,
            'vast_month_achievement_pct', a.vast_month_achievement_pct,
            'latest_allbrand_report_date', ab.report_date,
            'latest_allbrand_total_units', ab.competitor_units,
            'latest_allbrand_cumulative_total_units', ab.cumulative_units,
            'latest_allbrand_vivo_units', ab.vivo_units,
            'latest_allbrand_vivo_market_share', ab.vivo_market_share,
            'daily_target_all_type', a.target_daily_all_type,
            'actual_daily_all_type', a.actual_daily_all_type,
            'achievement_daily_all_type_pct', a.achievement_daily_all_type_pct,
            'daily_focus_target', a.target_daily_focus,
            'actual_daily_focus', a.actual_daily_focus,
            'achievement_daily_focus_pct', a.achievement_daily_focus_pct,
            'weekly_target_all_type', a.target_weekly_all_type,
            'actual_weekly_all_type', a.actual_weekly_all_type,
            'achievement_weekly_all_type_pct', a.achievement_weekly_all_type_pct,
            'weekly_focus_target', a.target_weekly_focus,
            'actual_weekly_focus', a.actual_weekly_focus,
            'achievement_weekly_focus_pct', a.achievement_weekly_focus_pct,
            'monthly_target_all_type', a.monthly_target_omzet,
            'actual_monthly_all_type', a.monthly_actual_omzet,
            'achievement_monthly_all_type_pct', a.monthly_achievement_omzet_pct,
            'monthly_focus_target', a.monthly_target_focus,
            'actual_monthly_focus', a.monthly_actual_focus,
            'achievement_monthly_focus_pct', a.monthly_achievement_focus_pct,
            'active_week_number', a.active_week_number,
            'active_week_start', a.active_week_start,
            'active_week_end', a.active_week_end,
            'period_start', a.period_start,
            'period_end', a.period_end,
            'active_week_snapshot', coalesce(a.active_week_snapshot, '{}'::jsonb),
            'daily_special_rows', coalesce(a.daily_special_rows, '[]'::jsonb),
            'weekly_special_rows', coalesce(a.weekly_special_rows, '[]'::jsonb),
            'monthly_special_rows', coalesce(a.monthly_special_rows, '[]'::jsonb),
            'vast_last_3_months', coalesce(vh.rows, '[]'::json),
            'home_snapshot', coalesce(a.home_snapshot, '{}'::jsonb)
          )
          order by a.display_name
        ),
        '[]'::json
      ) as rows
    from activity_by_promotor a
    left join latest_allbrand_by_promotor ab on ab.promotor_id = a.promotor_id
    left join vast_history_by_promotor vh on vh.promotor_id = a.promotor_id
  ),
  latest_allbrand as (
    select
      ar.id,
      ar.report_date,
      ar.promotor_id,
      coalesce(u.full_name, 'Promotor') as promotor_name,
      coalesce(ar.daily_total_units, 0)::int as competitor_units,
      coalesce(ar.cumulative_total_units, 0)::int as cumulative_units,
      coalesce((ar.vivo_auto_data ->> 'total')::int, 0) as vivo_units,
      case
        when coalesce(ar.daily_total_units, 0) + coalesce((ar.vivo_auto_data ->> 'total')::int, 0) > 0
        then round(
          (
            coalesce((ar.vivo_auto_data ->> 'total')::numeric, 0) /
            (coalesce(ar.daily_total_units, 0)::numeric + coalesce((ar.vivo_auto_data ->> 'total')::numeric, 0))
          ) * 100,
          1
        )
        else 0
      end as vivo_market_share
    from public.allbrand_reports ar
    left join public.users u on u.id = ar.promotor_id
    where ar.store_id = p_store_id
      and ar.report_date <= p_date
    order by ar.report_date desc, ar.updated_at desc nulls last, ar.created_at desc nulls last
    limit 1
  ),
  visit_summary as (
    select
      count(*) filter (
        where sv.visit_date >= date_trunc('month', p_date)::date
          and sv.visit_date < (date_trunc('month', p_date) + interval '1 month')::date
      )::int as visit_count,
      max(coalesce(sv.check_in_time, sv.created_at)) as last_visit_at
    from public.store_visits sv
    where sv.store_id = p_store_id
      and sv.sator_id = p_sator_id
  ),
  issue_summary as (
    select count(*)::int as issue_count
    from public.store_issues si
    where si.store_id = p_store_id
      and si.resolved = false
  ),
  vast_months as (
    select
      month_key,
      coalesce(sum(target_submissions), 0)::int as target_submissions,
      coalesce(sum(total_submissions), 0)::int as total_submissions,
      coalesce(sum(total_acc), 0)::int as total_acc,
      coalesce(sum(total_active_pending), 0)::int as total_active_pending,
      round(avg(achievement_pct), 1) as achievement_pct
    from public.vast_agg_monthly_promotor
    where store_id = p_store_id
      and month_key <= date_trunc('month', p_date)::date
      and promotor_id in (select promotor_id from active_promotors)
    group by month_key
    order by month_key desc
    limit 3
  ),
  priority_summary as (
    select json_build_object(
      'score',
      (
        case when (select issue_count from issue_summary) > 0 then 35 else 0 end +
        case when (select visit_count from visit_summary) = 0 then 25 else 0 end +
        case when (select visit_count from visit_summary) > 0
               and (select last_visit_at from visit_summary) < now() - interval '7 days' then 15 else 0 end +
        case when (select omzet from sales_today) < coalesce((select daily_target_omzet from target_summary), 0) then 15 else 0 end +
        case when (select focus_units from sales_today) <= 0 then 5 else 0 end +
        case when (select low_activity_count from activity_summary) > 0 then 10 else 0 end
      ),
      'reasons', to_json(array_remove(array[
        case when (select issue_count from issue_summary) > 0 then 'Ada issue toko yang belum selesai' end,
        case when (select visit_count from visit_summary) = 0 then 'Toko belum pernah divisit bulan ini' end,
        case when (select visit_count from visit_summary) > 0
               and (select last_visit_at from visit_summary) < now() - interval '7 days' then 'Sudah lama tidak divisit' end,
        case when (select omzet from sales_today) < coalesce((select daily_target_omzet from target_summary), 0) then 'Sell out di bawah target harian' end,
        case when (select focus_units from sales_today) <= 0 then 'Produk fokus belum bergerak' end,
        case when (select low_activity_count from activity_summary) > 0 then 'Ada promotor dengan aktivitas rendah' end
      ], null))
    ) as payload
  )
  select json_build_object(
    'target', json_build_object(
      'daily_achievement', coalesce((select omzet from sales_today), 0),
      'daily_target', round(coalesce((select daily_target_omzet from target_summary), 0)),
      'monthly_target', coalesce((select monthly_target_omzet from target_summary), 0),
      'fokus_achievement', coalesce((select focus_units from sales_today), 0),
      'fokus_target', round(coalesce((select daily_target_focus from target_summary), 0)),
      'vast_target', coalesce((select monthly_target_vast from target_summary), 0),
      'all_type_units', coalesce((select all_type_units from sales_today), 0)
    ),
    'activity', json_build_object(
      'promotor_count', coalesce((select promotor_count from activity_summary), 0),
      'present_count', coalesce((select present_count from activity_summary), 0),
      'low_activity_count', coalesce((select low_activity_count from activity_summary), 0),
      'rows', coalesce((select rows from activity_summary), '[]'::json)
    ),
    'promotors', coalesce((select rows from activity_summary), '[]'::json),
    'allbrand', (
      select case
        when exists(select 1 from latest_allbrand) then json_build_object(
          'has_data', true,
          'report_date', report_date,
          'promotor_name', promotor_name,
          'total_units', competitor_units,
          'vivo_units', vivo_units,
          'vivo_market_share', vivo_market_share,
          'cumulative_total_units', cumulative_units
        )
        else json_build_object(
          'has_data', false,
          'report_date', null,
          'promotor_name', null,
          'total_units', 0,
          'vivo_units', 0,
          'vivo_market_share', 0,
          'cumulative_total_units', 0
        )
      end
      from latest_allbrand
      union all
      select json_build_object(
        'has_data', false,
        'report_date', null,
        'promotor_name', null,
        'total_units', 0,
        'vivo_units', 0,
        'vivo_market_share', 0,
        'cumulative_total_units', 0
      )
      where not exists(select 1 from latest_allbrand)
      limit 1
    ),
    'visiting', json_build_object(
      'visit_count', coalesce((select visit_count from visit_summary), 0),
      'last_visit_at', (select last_visit_at from visit_summary),
      'issue_count', coalesce((select issue_count from issue_summary), 0)
    ),
    'vast_last_3_months', coalesce((
      select json_agg(
        json_build_object(
          'month_key', month_key,
          'target_submissions', target_submissions,
          'total_submissions', total_submissions,
          'total_acc', total_acc,
          'total_active_pending', total_active_pending,
          'achievement_pct', achievement_pct
        )
        order by month_key desc
      )
      from vast_months
    ), '[]'::json),
    'priority', coalesce((select payload from priority_summary), '{}'::json)
  )
  into v_result;

  return coalesce(v_result, '{}'::json);
end;
$function$;

grant execute on function public.get_sator_dynamic_target_rollup(uuid, date) to authenticated;
grant execute on function public.get_spv_dynamic_target_rollup(uuid, date) to authenticated;
grant execute on function public.get_sator_home_summary(uuid) to authenticated;
grant execute on function public.get_sator_home_weekly_snapshots(uuid, date) to authenticated;
grant execute on function public.get_spv_home_snapshot(uuid, date) to authenticated;
grant execute on function public.get_spv_home_weekly_snapshots(uuid, date) to authenticated;
grant execute on function public.get_sator_visiting_briefing(uuid, uuid, date) to authenticated;
