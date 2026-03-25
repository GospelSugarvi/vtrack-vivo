-- Fix SATOR home summary target source.
-- SATOR target weekly/monthly must come from the SATOR's own user_targets row,
-- not by summing promotor target_sell_out fields.

CREATE OR REPLACE FUNCTION public.get_sator_home_summary(p_sator_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
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
  v_daily_promotors json := '[]'::json;
  v_weekly_promotors json := '[]'::json;
  v_agenda json := '[]'::json;
  v_result json;
begin
  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from target_periods tp
  where current_date between tp.start_date and tp.end_date
  order by tp.start_date desc
  limit 1;

  if v_period_id is null then
    return json_build_object(
      'period', null,
      'counts', json_build_object('stores', 0, 'promotors', 0),
      'daily', json_build_object(),
      'weekly', json_build_object(),
      'monthly', json_build_object(),
      'daily_promotors', '[]'::json,
      'weekly_promotors', '[]'::json,
      'agenda', '[]'::json
    );
  end if;

  v_days := greatest((v_end - v_start) + 1, 1);
  v_day_index := greatest((current_date - v_start) + 1, 1);

  with promotor_ids as (
    select promotor_id
    from hierarchy_sator_promotor
    where sator_id = p_sator_id and active = true
  )
  select
    count(distinct aps.store_id),
    count(distinct pi.promotor_id)
  into v_store_count, v_promotor_count
  from promotor_ids pi
  left join assignments_promotor_store aps
    on aps.promotor_id = pi.promotor_id and aps.active = true;

  select
    coalesce(target_sell_out, 0),
    coalesce(target_fokus, 0),
    coalesce(target_sell_in, 0)
  into v_target_sellout, v_target_fokus, v_target_sellin
  from user_targets
  where period_id = v_period_id
    and user_id = p_sator_id
  order by updated_at desc
  limit 1;

  select coalesce(sum(s.price_at_transaction), 0),
         count(*),
         coalesce(sum(case when p.is_focus = true then 1 else 0 end), 0)
  into v_actual_sellout, v_today_units, v_actual_fokus
  from sales_sell_out s
  join hierarchy_sator_promotor hsp on hsp.promotor_id = s.promotor_id
  join product_variants pv on pv.id = s.variant_id
  join products p on p.id = pv.product_id
  where hsp.sator_id = p_sator_id
    and hsp.active = true
    and s.transaction_date between v_start and v_end
    and s.deleted_at is null
    and coalesce(s.is_chip_sale, false) = false;

  select coalesce(sum(total_value), 0)
  into v_actual_sellin
  from sales_sell_in
  where sator_id = p_sator_id
    and transaction_date between v_start and v_end
    and deleted_at is null;

  v_daily_target_sellout := v_target_sellout / v_days;
  v_daily_target_fokus := v_target_fokus / v_days;
  v_daily_target_sellin := v_target_sellin / v_days;

  select coalesce(sum(s.price_at_transaction), 0),
         count(*),
         coalesce(sum(case when p.is_focus = true then 1 else 0 end), 0)
  into v_today_sellout, v_today_units, v_today_fokus
  from sales_sell_out s
  join hierarchy_sator_promotor hsp on hsp.promotor_id = s.promotor_id
  join product_variants pv on pv.id = s.variant_id
  join products p on p.id = pv.product_id
  where hsp.sator_id = p_sator_id
    and hsp.active = true
    and s.transaction_date = current_date
    and s.deleted_at is null
    and coalesce(s.is_chip_sale, false) = false;

  select coalesce(sum(total_value), 0)
  into v_today_sellin
  from sales_sell_in
  where sator_id = p_sator_id
    and transaction_date = current_date
    and deleted_at is null;

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
    and (
      a.type = 'exception'
      or a.clock_in is not null
    );

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

  v_week_index := floor((current_date - v_start) / 7) + 1;
  v_week_start := v_start + (v_week_index - 1) * 7;
  v_week_end := least(v_week_start + 6, v_end);

  select percentage
  into v_week_pct
  from weekly_targets
  where period_id = v_period_id and week_number = v_week_index
  limit 1;

  if v_week_pct is null then
    v_week_pct := 25;
  end if;

  v_week_target_omzet := v_target_sellout * v_week_pct / 100;
  v_week_target_fokus := v_target_fokus * v_week_pct / 100;

  select coalesce(sum(s.price_at_transaction), 0),
         coalesce(sum(case when p.is_focus = true then 1 else 0 end), 0)
  into v_week_actual_omzet, v_week_actual_fokus
  from sales_sell_out s
  join hierarchy_sator_promotor hsp on hsp.promotor_id = s.promotor_id
  join product_variants pv on pv.id = s.variant_id
  join products p on p.id = pv.product_id
  where hsp.sator_id = p_sator_id
    and hsp.active = true
    and s.transaction_date between v_week_start and v_week_end
    and s.deleted_at is null
    and coalesce(s.is_chip_sale, false) = false;

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

  with promotor_ids as (
    select promotor_id
    from hierarchy_sator_promotor
    where sator_id = p_sator_id and active = true
  ),
  promotor_base as (
    select
      u.id as promotor_id,
      u.full_name,
      coalesce(ut.target_fokus_total, 0) as target_fokus_total
    from users u
    join promotor_ids pi on pi.promotor_id = u.id
    left join user_targets ut
      on ut.user_id = u.id and ut.period_id = v_period_id
  ),
  promotor_store as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      st.store_name
    from assignments_promotor_store aps
    join stores st on st.id = aps.store_id
    where aps.active = true
    order by aps.promotor_id, aps.created_at desc
  ),
  promotor_today as (
    select
      s.promotor_id,
      count(*) filter (where p.is_focus = true) as fokus_units_today
    from sales_sell_out s
    join product_variants pv on pv.id = s.variant_id
    join products p on p.id = pv.product_id
    where s.transaction_date = current_date
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
    group by s.promotor_id
  )
  select coalesce(json_agg(
    json_build_object(
      'promotor_id', pb.promotor_id,
      'name', pb.full_name,
      'store_name', coalesce(ps.store_name, '-'),
      'target_units', case when v_days > 0 then (pb.target_fokus_total / v_days) else 0 end,
      'actual_units', coalesce(pt.fokus_units_today, 0),
      'achievement_pct',
        case when v_days > 0 and (pb.target_fokus_total / v_days) > 0
          then (coalesce(pt.fokus_units_today, 0) * 100 / (pb.target_fokus_total / v_days))
          else 0 end
    ) order by pb.full_name
  ), '[]'::json)
  into v_daily_promotors
  from promotor_base pb
  left join promotor_store ps on ps.promotor_id = pb.promotor_id
  left join promotor_today pt on pt.promotor_id = pb.promotor_id;

  with promotor_ids as (
    select promotor_id
    from hierarchy_sator_promotor
    where sator_id = p_sator_id and active = true
  ),
  promotor_base as (
    select
      u.id as promotor_id,
      u.full_name,
      coalesce(ut.target_fokus_total, 0) as target_fokus_total
    from users u
    join promotor_ids pi on pi.promotor_id = u.id
    left join user_targets ut
      on ut.user_id = u.id and ut.period_id = v_period_id
  ),
  promotor_week as (
    select
      s.promotor_id,
      count(*) as units_week
    from sales_sell_out s
    where s.transaction_date between v_week_start and v_week_end
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
    group by s.promotor_id
  )
  select coalesce(json_agg(
    json_build_object(
      'promotor_id', pb.promotor_id,
      'name', pb.full_name,
      'units_week', coalesce(pw.units_week, 0),
      'target_units', (pb.target_fokus_total * v_week_pct / 100),
      'achievement_pct',
        case when (pb.target_fokus_total * v_week_pct / 100) > 0
          then (coalesce(pw.units_week, 0) * 100 / (pb.target_fokus_total * v_week_pct / 100))
          else 0 end
    ) order by pb.full_name
  ), '[]'::json)
  into v_weekly_promotors
  from promotor_base pb
  left join promotor_week pw on pw.promotor_id = pb.promotor_id;

  select coalesce(json_agg(item), '[]'::json)
  into v_agenda
  from (
    select json_build_object(
      'type', 'schedule',
      'title', 'Approve Jadwal',
      'sub', v_report_pending::text || ' pending',
      'status', case when v_report_pending > 0 then 'pending' else 'ok' end
    ) as item
    union all
    select json_build_object(
      'type', 'visiting',
      'title', 'Visiting',
      'sub', coalesce(st.store_name, 'Tidak ada visiting'),
      'status', case when sv.id is null then 'idle' else 'done' end
    )
    from (
      select id, store_id
      from store_visits
      where sator_id = p_sator_id
        and visit_date = current_date
      order by created_at desc
      limit 1
    ) sv
    left join stores st on st.id = sv.store_id
    union all
    select json_build_object(
      'type', 'sellin',
      'title', 'Finalisasi Sell In',
      'sub', coalesce(count(*),0)::text || ' order pending',
      'status', case when count(*) > 0 then 'process' else 'ok' end
    )
    from orders
    where sator_id = p_sator_id
      and status in ('pending','processing')
    union all
    select json_build_object(
      'type', 'imei',
      'title', 'Penormalan IMEI',
      'sub', coalesce(count(*),0)::text || ' unit',
      'status', case when count(*) > 0 then 'review' else 'ok' end
    )
    from imei_records
    where promotor_id in (
      select promotor_id from hierarchy_sator_promotor
      where sator_id = p_sator_id and active = true
    )
      and normalization_status <> 'completed'
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
      'target_per_day', case when v_days - v_day_index > 0
        then (v_target_sellout - v_actual_sellout) / (v_days - v_day_index)
        else 0 end
    ),
    'daily_promotors', v_daily_promotors,
    'weekly_promotors', v_weekly_promotors,
    'agenda', v_agenda
  );

  return v_result;
end;
$function$;
