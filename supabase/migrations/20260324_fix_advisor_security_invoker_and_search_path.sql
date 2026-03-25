create or replace view public.v_bonus_event_details
with (security_invoker = on)
as
select
  sbe.id as bonus_event_id,
  sbe.user_id,
  sbe.period_id,
  sbe.sales_sell_out_id,
  sso.transaction_date,
  sso.serial_imei,
  sso.variant_id,
  sso.price_at_transaction,
  sso.is_chip_sale,
  sbe.bonus_type,
  sbe.bonus_amount,
  sbe.is_projection,
  sbe.calculation_version,
  sbe.rule_id,
  sbe.rule_snapshot,
  sbe.notes,
  sbe.created_at
from public.sales_bonus_events sbe
join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id;

create or replace view public.v_bonus_parity_dashboard_vs_events
with (security_invoker = on)
as
with event_totals as (
  select
    sbe.user_id,
    sbe.period_id,
    coalesce(sum(sbe.bonus_amount), 0::numeric) as total_bonus_events
  from public.sales_bonus_events sbe
  where sbe.period_id is not null
  group by sbe.user_id, sbe.period_id
),
dashboard_totals as (
  select
    dpm.user_id,
    dpm.period_id,
    coalesce(dpm.estimated_bonus_total, 0::numeric) as total_bonus_dashboard
  from public.dashboard_performance_metrics dpm
  where dpm.user_id is not null
    and dpm.period_id is not null
)
select
  dt.user_id,
  dt.period_id,
  dt.total_bonus_dashboard,
  coalesce(et.total_bonus_events, 0::numeric) as total_bonus_events,
  coalesce(et.total_bonus_events, 0::numeric) - dt.total_bonus_dashboard as bonus_gap,
  case
    when dt.total_bonus_dashboard = coalesce(et.total_bonus_events, 0::numeric) then 'MATCH'::text
    else 'MISMATCH'::text
  end as parity_status
from dashboard_totals dt
left join event_totals et
  on et.user_id = dt.user_id
 and et.period_id = dt.period_id;

create or replace view public.v_bonus_summary
with (security_invoker = on)
as
select
  u.id as user_id,
  u.full_name,
  u.role,
  u.promotor_type,
  tp.period_name,
  tp.target_month,
  tp.target_year,
  dpm.total_omzet_real,
  dpm.total_units_sold,
  dpm.total_units_focus,
  dpm.estimated_bonus_total,
  dpm.last_updated,
  case
    when ut.target_omzet > 0::numeric then round((dpm.total_omzet_real / ut.target_omzet) * 100::numeric, 2)
    else 0::numeric
  end as achievement_pct
from public.dashboard_performance_metrics dpm
join public.users u on u.id = dpm.user_id
join public.target_periods tp on tp.id = dpm.period_id
left join public.user_targets ut
  on ut.user_id = u.id
 and ut.period_id = tp.id
where u.deleted_at is null
order by tp.start_date desc, dpm.estimated_bonus_total desc;

create or replace view public.v_bonus_summary_from_events
with (security_invoker = on)
as
select
  sbe.user_id,
  sbe.period_id,
  count(*) as bonus_event_count,
  coalesce(sum(sbe.bonus_amount), 0::numeric) as total_bonus,
  count(*) filter (where sbe.bonus_type = 'range'::text) as range_event_count,
  count(*) filter (where sbe.bonus_type = 'flat'::text) as flat_event_count,
  count(*) filter (where sbe.bonus_type = 'ratio'::text) as ratio_event_count,
  count(*) filter (where sbe.bonus_type = 'chip'::text) as chip_event_count,
  count(*) filter (where sbe.bonus_type = 'excluded'::text) as excluded_event_count,
  max(sbe.created_at) as last_event_at
from public.sales_bonus_events sbe
group by sbe.user_id, sbe.period_id;

create or replace view public.v_daily_activity_status
with (security_invoker = on)
as
select
  u.id as user_id,
  u.full_name,
  at.id as activity_type_id,
  at.name as activity_name,
  at.is_required,
  (now() at time zone 'Asia/Makassar')::date as today,
  case
    when ar.id is not null then true
    else false
  end as completed
from public.users u
cross join public.activity_types at
left join public.activity_records ar
  on ar.user_id = u.id
 and ar.activity_type_id = at.id
 and ar.activity_date = (now() at time zone 'Asia/Makassar')::date
where u.role = 'promotor'::public.user_role
  and u.deleted_at is null
  and at.is_active = true
  and at.target_role = any (array['promotor'::text, 'all'::text]);

create or replace view public.v_index_efficiency
with (security_invoker = on)
as
select
  schemaname,
  relname as table_name,
  indexrelname as index_name,
  idx_scan,
  case
    when idx_scan = 0 then '🔴 UNUSED'::text
    when idx_scan < 10 then '🟡 LOW'::text
    else '🟢 ACTIVE'::text
  end as usage_level
from pg_stat_user_indexes
order by idx_scan desc;

create or replace view public.v_stock_alerts
with (security_invoker = on)
as
select
  st.id as store_id,
  st.store_name,
  p.id as product_id,
  p.model_name,
  pv.id as variant_id,
  pv.ram_rom,
  pv.color,
  coalesce(stock_count.count, 0::bigint) as current_stock,
  public.get_effective_min_stock(st.id, p.id, pv.id) as min_stock,
  case
    when coalesce(stock_count.count, 0::bigint) = 0 then 'empty'::text
    when coalesce(stock_count.count, 0::bigint) < public.get_effective_min_stock(st.id, p.id, pv.id) then 'low'::text
    else 'ok'::text
  end as status
from public.stores st
cross join public.products p
cross join public.product_variants pv
left join (
  select
    stok.store_id,
    stok.variant_id,
    count(*) as count
  from public.stok
  where stok.is_sold = false
  group by stok.store_id, stok.variant_id
) stock_count
  on stock_count.store_id = st.id
 and stock_count.variant_id = pv.id
where pv.product_id = p.id
  and pv.active = true
  and st.deleted_at is null
  and p.deleted_at is null;

create or replace view public.v_stok_toko
with (security_invoker = on)
as
select
  s.store_id,
  s.product_id,
  s.variant_id,
  p.model_name,
  pv.ram_rom,
  pv.color,
  count(*) filter (where s.tipe_stok::text = 'fresh'::text and s.is_sold = false) as fresh_count,
  count(*) filter (where s.tipe_stok::text = 'chip'::text and s.is_sold = false) as chip_count,
  count(*) filter (where s.tipe_stok::text = 'display'::text and s.is_sold = false) as display_count,
  count(*) filter (where s.is_sold = false) as total_available
from public.stok s
join public.products p on p.id = s.product_id
join public.product_variants pv on pv.id = s.variant_id
where s.is_sold = false
group by s.store_id, s.product_id, s.variant_id, p.model_name, pv.ram_rom, pv.color;

create or replace view public.v_table_sizes
with (security_invoker = on)
as
select
  schemaname,
  relname as table_name,
  pg_size_pretty(pg_total_relation_size((schemaname || '.' || relname)::regclass)) as total_size,
  n_live_tup as row_count
from pg_stat_user_tables
order by pg_total_relation_size((schemaname || '.' || relname)::regclass) desc;

create or replace view public.v_table_stats
with (security_invoker = on)
as
select
  schemaname,
  relname as table_name,
  n_live_tup as live_rows,
  n_dead_tup as dead_rows,
  case
    when n_dead_tup > n_live_tup then '🔴 HIGH BLOAT'::text
    when n_dead_tup > n_live_tup / 2 then '🟡 MODERATE BLOAT'::text
    else '🟢 LOW BLOAT'::text
  end as bloat_status,
  last_vacuum,
  last_analyze
from pg_stat_user_tables
order by n_dead_tup desc;

create or replace function public.update_schedule_review_comments_updated_at()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

create or replace function public.copy_previous_month_schedule(p_promotor_id uuid, p_target_month text)
returns table(success boolean, message text, copied_count integer)
language plpgsql
security definer
set search_path = public
as $function$
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
    select 1
    from public.schedules
    where promotor_id = p_promotor_id
      and month_year = p_target_month
  ) then
    return query select false, 'Target month already has schedules. Delete them first.', 0;
    return;
  end if;

  if not exists (
    select 1
    from public.schedules
    where promotor_id = p_promotor_id
      and month_year = v_previous_month
  ) then
    return query select false, 'No schedules found in previous month to copy.', 0;
    return;
  end if;

  for v_schedule_record in
    select
      shift_type,
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
        month_year
      ) values (
        p_promotor_id,
        (p_target_month || '-' || lpad(v_schedule_record.day_num::text, 2, '0'))::date,
        v_schedule_record.shift_type,
        'draft',
        p_target_month
      );
      v_copied_count := v_copied_count + 1;
    end if;
  end loop;

  return query
  select true, 'Successfully copied ' || v_copied_count || ' schedules from ' || v_previous_month, v_copied_count;
end;
$function$;

create or replace function public.get_current_target_period()
returns uuid
language plpgsql
set search_path = public
as $function$
declare
  v_current_month integer;
  v_current_year integer;
begin
  v_current_month := extract(month from current_date);
  v_current_year := extract(year from current_date);

  return public.get_or_create_target_period(v_current_month, v_current_year);
end;
$function$;

create or replace function public.get_fokus_products_by_period(p_period_id uuid)
returns table(product_id uuid, model_name text, series text, is_detail_target boolean, is_special boolean)
language plpgsql
stable
set search_path = public
as $function$
begin
  return query
  select
    p.id as product_id,
    p.model_name,
    p.series,
    coalesce(fp.is_detail_target, false) as is_detail_target,
    coalesce(fp.is_special, false) as is_special
  from public.fokus_products fp
  join public.products p on p.id = fp.product_id
  where fp.period_id = p_period_id
    and p.status = 'active'
    and p.deleted_at is null
  order by p.series, p.model_name;
end;
$function$;

create or replace function public.get_pending_schedules(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
begin
  return (
    with promotor_ids as (
      select promotor_id
      from public.hierarchy_sator_promotor
      where sator_id = p_sator_id
        and active = true
    )
    select coalesce(
      json_agg(
        json_build_object(
          'id', sr.id,
          'promotor_id', sr.user_id,
          'promotor_name', u.full_name,
          'type', sr.schedule_type,
          'date', sr.schedule_date,
          'reason', sr.reason,
          'status', sr.status,
          'created_at', sr.created_at
        )
        order by sr.created_at desc
      ),
      '[]'::json
    )
    from public.schedule_requests sr
    join public.users u on u.id = sr.user_id
    where sr.user_id in (select promotor_id from promotor_ids)
      and sr.status = 'pending'
  );
end;
$function$;

create or replace function public.get_sator_kpi_detail(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_current_month text;
begin
  v_current_month := to_char(current_date, 'YYYY-MM');

  return (
    select json_build_object(
      'sell_out_all', coalesce(sell_out_all_score, 0),
      'sell_out_fokus', coalesce(sell_out_fokus_score, 0),
      'sell_in', coalesce(sell_in_score, 0),
      'kpi_ma', coalesce(kpi_ma_score, 0),
      'total_score', coalesce(total_score, 0)
    )
    from public.sator_monthly_kpi
    where sator_id = p_sator_id
      and period_month = v_current_month
  );
end;
$function$;

create or replace function public.get_sator_sales_per_promotor(p_sator_id uuid, p_period text default null::text)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_period text;
begin
  v_period := coalesce(p_period, to_char(current_date, 'YYYY-MM'));

  return (
    with promotor_ids as (
      select promotor_id
      from public.hierarchy_sator_promotor
      where sator_id = p_sator_id
        and active = true
    )
    select coalesce(
      json_agg(
        json_build_object(
          'promotor_id', u.id,
          'promotor_name', u.full_name,
          'promotor_type', u.promotor_type,
          'total_units', coalesce(sum(s.quantity), 0),
          'total_revenue', coalesce(sum(s.price_at_transaction), 0)
        )
      ),
      '[]'::json
    )
    from public.users u
    join promotor_ids pi on pi.promotor_id = u.id
    left join public.sell_out s
      on s.promotor_id = u.id
     and to_char(s.sale_date at time zone 'Asia/Makassar', 'YYYY-MM') = v_period
    group by u.id, u.full_name, u.promotor_type
    order by coalesce(sum(s.quantity), 0) desc
  );
end;
$function$;

create or replace function public.get_sator_sales_per_toko(p_sator_id uuid, p_period text default null::text)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_period text;
begin
  v_period := coalesce(p_period, to_char(current_date, 'YYYY-MM'));

  return (
    with promotor_ids as (
      select promotor_id
      from public.hierarchy_sator_promotor
      where sator_id = p_sator_id
        and active = true
    )
    select coalesce(
      json_agg(
        json_build_object(
          'store_id', st.id,
          'store_name', st.store_name,
          'total_units', coalesce(sum(s.quantity), 0),
          'total_revenue', coalesce(sum(s.price_at_transaction), 0)
        )
      ),
      '[]'::json
    )
    from public.stores st
    join public.assignments_promotor_store aps on aps.store_id = st.id
    join promotor_ids pi on pi.promotor_id = aps.promotor_id
    left join public.sell_out s
      on s.store_id = st.id
     and to_char(s.sale_date at time zone 'Asia/Makassar', 'YYYY-MM') = v_period
    where aps.active = true
    group by st.id, st.store_name
    order by coalesce(sum(s.quantity), 0) desc
  );
end;
$function$;

create or replace function public.get_sator_stores(p_sator_id uuid)
returns json
language sql
security definer
set search_path = public
as $function$
  select coalesce(
    json_agg(
      json_build_object(
        'store_id', st.id,
        'store_name', st.store_name,
        'address', st.address,
        'promotor_count', (
          select count(*)
          from public.assignments_promotor_store aps2
          where aps2.store_id = st.id
            and aps2.active = true
        )
      )
    ),
    '[]'::json
  )
  from public.stores st
  join public.assignments_promotor_store aps on aps.store_id = st.id
  join public.hierarchy_sator_promotor hsp on hsp.promotor_id = aps.promotor_id
  where hsp.sator_id = p_sator_id
    and hsp.active = true
    and aps.active = true
  group by st.id, st.store_name, st.address;
$function$;

create or replace function public.get_sator_visiting_stores(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
begin
  return (
    with promotor_ids as (
      select promotor_id
      from public.hierarchy_sator_promotor
      where sator_id = p_sator_id
        and active = true
    ),
    store_ids as (
      select distinct store_id
      from public.assignments_promotor_store
      where promotor_id in (select promotor_id from promotor_ids)
        and active = true
    )
    select coalesce(
      json_agg(
        json_build_object(
          'store_id', st.id,
          'store_name', st.store_name,
          'address', st.address,
          'last_visit', (
            select max(sv.created_at)
            from public.store_visits sv
            where sv.store_id = st.id
          ),
          'issue_count', (
            select count(*)
            from public.store_issues si
            where si.store_id = st.id
              and si.resolved = false
          ),
          'priority', case
            when (
              select count(*)
              from public.store_issues si
              where si.store_id = st.id
                and si.resolved = false
            ) > 0 then 1
            when (
              select max(sv.created_at)
              from public.store_visits sv
              where sv.store_id = st.id
            ) is null then 2
            when (
              select max(sv.created_at)
              from public.store_visits sv
              where sv.store_id = st.id
            ) < now() - interval '7 days' then 3
            else 4
          end
        )
      ),
      '[]'::json
    )
    from public.stores st
    where st.id in (select store_id from store_ids)
    order by case
      when (
        select count(*)
        from public.store_issues si
        where si.store_id = st.id
          and si.resolved = false
      ) > 0 then 1
      when (
        select max(sv.created_at)
        from public.store_visits sv
        where sv.store_id = st.id
      ) is null then 2
      else 3
    end
  );
end;
$function$;

create or replace function public.get_stock_summary_by_store()
returns table(store_id uuid, store_name text, fresh_count bigint, chip_count bigint, display_count bigint)
language plpgsql
security definer
set search_path = public
as $function$
begin
  return query
  select
    st.id as store_id,
    st.store_name,
    coalesce(count(*) filter (where s.tipe_stok = 'fresh'), 0)::bigint as fresh_count,
    coalesce(count(*) filter (where s.tipe_stok = 'chip'), 0)::bigint as chip_count,
    coalesce(count(*) filter (where s.tipe_stok = 'display'), 0)::bigint as display_count
  from public.stores st
  left join public.stok s
    on s.store_id = st.id
   and s.is_sold = false
  where st.deleted_at is null
  group by st.id, st.store_name
  order by st.store_name;
end;
$function$;

create or replace function public.get_target_dashboard(p_user_id uuid, p_period_id uuid default null::uuid)
returns table(
  period_id uuid,
  period_name text,
  start_date date,
  end_date date,
  target_omzet numeric,
  actual_omzet numeric,
  achievement_omzet_pct numeric,
  target_fokus_total integer,
  actual_fokus_total integer,
  achievement_fokus_pct numeric,
  fokus_details jsonb,
  weekly_breakdown jsonb,
  time_gone_pct numeric,
  status_omzet text,
  status_fokus text,
  warning_omzet boolean,
  warning_fokus boolean
)
language plpgsql
stable
set search_path = public
as $function$
begin
  if p_period_id is not null then
    return query
    select tp.id, tp.period_name, tp.start_date, tp.end_date, ta.*
    from public.target_periods tp
    left join lateral public.calculate_target_achievement(p_user_id, tp.id) ta on true
    where tp.id = p_period_id;
  else
    return query
    select tp.id, tp.period_name, tp.start_date, tp.end_date, ta.*
    from public.target_periods tp
    left join lateral public.calculate_target_achievement(p_user_id, tp.id) ta on true
    where tp.deleted_at is null
      and tp.status = 'active'
    order by tp.target_year desc, tp.target_month desc, tp.created_at desc
    limit 1;
  end if;
end;
$function$;

create or replace function public.get_team_calendar(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
begin
  return (
    with promotor_ids as (
      select promotor_id
      from public.hierarchy_sator_promotor
      where sator_id = p_sator_id
        and active = true
    )
    select coalesce(
      json_agg(
        json_build_object(
          'id', sr.id,
          'promotor_id', sr.user_id,
          'promotor_name', u.full_name,
          'type', sr.schedule_type,
          'date', sr.schedule_date,
          'status', sr.status
        )
      ),
      '[]'::json
    )
    from public.schedule_requests sr
    join public.users u on u.id = sr.user_id
    where sr.user_id in (select promotor_id from promotor_ids)
      and sr.schedule_date >= current_date
      and sr.status = 'approved'
    order by sr.schedule_date
  );
end;
$function$;

create or replace function public.update_weekly_targets_updated_at()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;
