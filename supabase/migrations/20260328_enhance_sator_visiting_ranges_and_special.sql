create or replace function public.get_sator_visiting_briefing(
  p_sator_id uuid,
  p_store_id uuid,
  p_date date default current_date
)
returns json
language plpgsql
security definer
set search_path = public
as $$
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
      coalesce(
        sum(coalesce((hs.snapshot -> 'monthly_target' ->> 'target_omzet')::numeric, 0)),
        0
      )::int as monthly_target_omzet,
      coalesce(
        sum(coalesce((hs.snapshot -> 'monthly_target' ->> 'target_fokus_total')::numeric, 0)),
        0
      )::int as monthly_target_focus,
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
            'home_snapshot', coalesce(a.home_snapshot, '{}'::jsonb),
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
      count(*)::int as visit_count,
      max(sv.created_at) as last_visit_at
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
        case when (select omzet from sales_today) < round((select monthly_target_omzet from target_summary) / 30.0) then 15 else 0 end +
        case when (select focus_units from sales_today) <= 0 then 5 else 0 end +
        case when (select low_activity_count from activity_summary) > 0 then 10 else 0 end
      ),
      'reasons', to_json(array_remove(array[
        case when (select issue_count from issue_summary) > 0 then 'Ada issue toko yang belum selesai' end,
        case when (select visit_count from visit_summary) = 0 then 'Toko belum pernah divisit' end,
        case when (select visit_count from visit_summary) > 0
               and (select last_visit_at from visit_summary) < now() - interval '7 days' then 'Sudah lama tidak divisit' end,
        case when (select omzet from sales_today) < round((select monthly_target_omzet from target_summary) / 30.0) then 'Sell out di bawah target harian' end,
        case when (select focus_units from sales_today) <= 0 then 'Produk fokus belum bergerak' end,
        case when (select low_activity_count from activity_summary) > 0 then 'Ada promotor dengan aktivitas rendah' end
      ], null))
    ) as payload
  )
  select json_build_object(
    'target', json_build_object(
      'daily_achievement', coalesce((select omzet from sales_today), 0),
      'daily_target', round(coalesce((select monthly_target_omzet from target_summary), 0) / 30.0),
      'monthly_target', coalesce((select monthly_target_omzet from target_summary), 0),
      'fokus_achievement', coalesce((select focus_units from sales_today), 0),
      'fokus_target', round(coalesce((select monthly_target_focus from target_summary), 0) / 30.0),
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
$$;

grant execute on function public.get_sator_visiting_briefing(uuid, uuid, date) to authenticated;

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
      least(coalesce(cp.month_end, (date_trunc('month', p_date) + interval '1 month - 1 day')::date), p_date) as month_end,
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
      ) as month_allbrand_count
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
        'month_attendance_days', coalesce(r.month_attendance_days, 0),
        'month_sellout_count', coalesce(r.month_sellout_count, 0),
        'month_stock_input_count', coalesce(r.month_stock_input_count, 0),
        'month_promotion_count', coalesce(r.month_promotion_count, 0),
        'month_follower_count', coalesce(r.month_follower_count, 0),
        'month_allbrand_count', coalesce(r.month_allbrand_count, 0)
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
