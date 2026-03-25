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
        'achievement_pct_monthly', v_achievement_pct_monthly
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
    'sator_cards', v_sator_cards
  );
end;
$function$;

grant execute on function public.get_spv_home_snapshot(uuid, date) to authenticated;
