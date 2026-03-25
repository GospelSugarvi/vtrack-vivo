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
  target_summary as (
    select
      coalesce(sum(ut.target_omzet), 0)::int as monthly_target_omzet,
      coalesce(sum(ut.target_fokus_total), 0)::int as monthly_target_focus,
      coalesce(sum(ut.target_vast), 0)::int as monthly_target_vast
    from public.user_targets ut
    where ut.user_id in (select promotor_id from active_promotors)
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
      ) as allbrand_sent
    from active_promotors ap
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
            'promotor_id', promotor_id,
            'promotor_name', display_name,
            'clock_in', clock_in,
            'sales_count', sales_count,
            'stock_count', stock_count,
            'allbrand_sent', allbrand_sent
          )
          order by display_name
        ),
        '[]'::json
      ) as rows
    from activity_by_promotor
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
