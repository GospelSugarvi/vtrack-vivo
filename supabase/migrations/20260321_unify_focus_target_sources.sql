create or replace function public.get_target_focus_product_ids(
  p_period_id uuid,
  p_target_fokus_detail jsonb default '{}'::jsonb,
  p_target_special_detail jsonb default '{}'::jsonb
)
returns table(product_id uuid)
language sql
stable
as $$
  with legacy_detail_products as (
    select distinct p.id as product_id
    from jsonb_each(coalesce(p_target_fokus_detail, '{}'::jsonb)) d
    join public.fokus_bundles fb on fb.id::text = d.key
    join public.products p on p.model_name = any(fb.product_types)
    where p.status = 'active'
      and p.deleted_at is null
  ),
  special_products as (
    select distinct sbp.product_id
    from jsonb_each(coalesce(p_target_special_detail, '{}'::jsonb)) d
    join public.special_focus_bundles sb
      on sb.id::text = d.key
     and sb.period_id = p_period_id
    join public.special_focus_bundle_products sbp on sbp.bundle_id = sb.id
  )
  select distinct lp.product_id
  from legacy_detail_products lp
  union
  select distinct sp.product_id
  from special_products sp;
$$;

grant execute on function public.get_target_focus_product_ids(uuid, jsonb, jsonb) to authenticated;

create or replace function public.calculate_target_achievement(
  p_user_id uuid,
  p_period_id uuid
)
returns table(
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
as $$
declare
  v_time_gone numeric;
  v_target_omzet numeric := 0;
  v_actual_omzet numeric := 0;
  v_achievement_omzet numeric := 0;
  v_target_fokus integer := 0;
  v_actual_fokus integer := 0;
  v_achievement_fokus numeric := 0;
  v_fokus_details_detail jsonb := '[]'::jsonb;
  v_fokus_details_special jsonb := '[]'::jsonb;
  v_fokus_details jsonb := '[]'::jsonb;
  v_weekly_breakdown jsonb := '[]'::jsonb;
  v_target_fokus_detail jsonb := '{}'::jsonb;
  v_target_special_detail jsonb := '{}'::jsonb;
  v_effective_legacy_detail jsonb := '{}'::jsonb;
  v_effective_special_detail jsonb := '{}'::jsonb;
  v_start_date date;
  v_end_date date;
  v_has_focus_detail boolean := false;
begin
  v_time_gone := public.get_time_gone_percentage(p_period_id);

  select tp.start_date, tp.end_date
  into v_start_date, v_end_date
  from public.target_periods tp
  where tp.id = p_period_id;

  select
    coalesce(ut.target_sell_out, 0),
    coalesce(ut.target_fokus_detail, '{}'::jsonb),
    coalesce(ut.target_special_detail, '{}'::jsonb),
    coalesce(ut.target_fokus_total, 0)
  into
    v_target_omzet,
    v_target_fokus_detail,
    v_target_special_detail,
    v_target_fokus
  from public.user_targets ut
  where ut.user_id = p_user_id
    and ut.period_id = p_period_id
  order by ut.updated_at desc
  limit 1;

  if v_target_special_detail <> '{}'::jsonb then
    v_effective_special_detail := v_target_special_detail;
    v_effective_legacy_detail := '{}'::jsonb;
  else
    v_effective_special_detail := '{}'::jsonb;
    v_effective_legacy_detail := v_target_fokus_detail;
  end if;

  v_has_focus_detail :=
    v_effective_legacy_detail <> '{}'::jsonb
    or v_effective_special_detail <> '{}'::jsonb;

  if v_target_fokus <= 0 then
    v_target_fokus := (
      coalesce((
        select sum((value::text)::numeric)
        from jsonb_each(v_effective_legacy_detail)
      ), 0)
      +
      coalesce((
        select sum((value::text)::numeric)
        from jsonb_each(v_effective_special_detail)
      ), 0)
    )::int;
  end if;

  select dpm.total_omzet_real
  into v_actual_omzet
  from public.dashboard_performance_metrics dpm
  where dpm.user_id = p_user_id
    and dpm.period_id = p_period_id;

  if v_actual_omzet is null then
    select coalesce(sum(sso.price_at_transaction), 0)
    into v_actual_omzet
    from public.sales_sell_out sso
    where sso.promotor_id = p_user_id
      and sso.transaction_date >= v_start_date
      and sso.transaction_date <= v_end_date
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false;
  end if;

  if v_has_focus_detail then
    select coalesce(count(*), 0)
    into v_actual_fokus
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date >= v_start_date
      and sso.transaction_date <= v_end_date
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
      and exists (
        select 1
        from public.get_target_focus_product_ids(
          p_period_id,
          v_effective_legacy_detail,
          v_effective_special_detail
        ) tp
        where tp.product_id = pv.product_id
      );
  else
    select dpm.total_units_focus
    into v_actual_fokus
    from public.dashboard_performance_metrics dpm
    where dpm.user_id = p_user_id
      and dpm.period_id = p_period_id;

    if v_actual_fokus is null then
      select coalesce(count(*), 0)
      into v_actual_fokus
      from public.sales_sell_out sso
      join public.product_variants pv on pv.id = sso.variant_id
      join public.products p on p.id = pv.product_id
      where sso.promotor_id = p_user_id
        and sso.transaction_date >= v_start_date
        and sso.transaction_date <= v_end_date
        and sso.deleted_at is null
        and coalesce(sso.is_chip_sale, false) = false
        and coalesce(p.is_focus, false) = true;
    end if;
  end if;

  if v_target_omzet > 0 then
    v_achievement_omzet := (v_actual_omzet / v_target_omzet) * 100;
  end if;

  if v_target_fokus > 0 then
    v_achievement_fokus := (v_actual_fokus::numeric / v_target_fokus::numeric) * 100;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'bundle_id', x.bundle_id,
        'bundle_name', x.bundle_name,
        'target_qty', x.target_qty,
        'actual_qty', x.actual_qty,
        'achievement_pct',
          case
            when x.target_qty > 0 then round((x.actual_qty::numeric / x.target_qty::numeric) * 100, 2)
            else 0
          end
      )
      order by x.bundle_name
    ),
    '[]'::jsonb
  )
  into v_fokus_details_detail
  from (
    select
      fb.id as bundle_id,
      fb.bundle_name,
      (d.value::text)::int as target_qty,
      (
        select coalesce(count(*), 0)
        from public.sales_sell_out sso
        join public.product_variants pv on pv.id = sso.variant_id
        join public.products p on p.id = pv.product_id
        where sso.promotor_id = p_user_id
          and sso.transaction_date >= v_start_date
          and sso.transaction_date <= v_end_date
          and sso.deleted_at is null
          and coalesce(sso.is_chip_sale, false) = false
          and p.model_name = any(fb.product_types)
      ) as actual_qty
    from jsonb_each(v_effective_legacy_detail) d
    join public.fokus_bundles fb on fb.id::text = d.key
  ) x;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'bundle_id', x.bundle_id,
        'bundle_name', x.bundle_name,
        'target_qty', x.target_qty,
        'actual_qty', x.actual_qty,
        'achievement_pct',
          case
            when x.target_qty > 0 then round((x.actual_qty::numeric / x.target_qty::numeric) * 100, 2)
            else 0
          end
      )
      order by x.bundle_name
    ),
    '[]'::jsonb
  )
  into v_fokus_details_special
  from (
    select
      sb.id as bundle_id,
      sb.bundle_name,
      (d.value::text)::int as target_qty,
      (
        select coalesce(count(*), 0)
        from public.sales_sell_out sso
        join public.product_variants pv on pv.id = sso.variant_id
        join public.special_focus_bundle_products sbp on sbp.product_id = pv.product_id
        where sbp.bundle_id = sb.id
          and sso.promotor_id = p_user_id
          and sso.transaction_date >= v_start_date
          and sso.transaction_date <= v_end_date
          and sso.deleted_at is null
          and coalesce(sso.is_chip_sale, false) = false
      ) as actual_qty
    from jsonb_each(v_effective_special_detail) d
    join public.special_focus_bundles sb
      on sb.id::text = d.key
     and sb.period_id = p_period_id
  ) x;

  v_fokus_details := coalesce(v_fokus_details_detail, '[]'::jsonb) || coalesce(v_fokus_details_special, '[]'::jsonb);
  v_weekly_breakdown := public.calculate_weekly_breakdown(p_user_id, p_period_id);

  return query
  select
    v_target_omzet,
    coalesce(v_actual_omzet, 0),
    round(coalesce(v_achievement_omzet, 0), 2),
    v_target_fokus,
    coalesce(v_actual_fokus, 0),
    round(coalesce(v_achievement_fokus, 0), 2),
    v_fokus_details,
    v_weekly_breakdown,
    v_time_gone,
    case
      when coalesce(v_achievement_omzet, 0) >= 100 then 'ACHIEVED'
      when coalesce(v_achievement_omzet, 0) >= v_time_gone then 'ON_TRACK'
      else 'WARNING'
    end,
    case
      when coalesce(v_achievement_fokus, 0) >= 100 then 'ACHIEVED'
      when coalesce(v_achievement_fokus, 0) >= v_time_gone then 'ON_TRACK'
      else 'WARNING'
    end,
    (coalesce(v_achievement_omzet, 0) < v_time_gone and v_target_omzet > 0),
    (coalesce(v_achievement_fokus, 0) < v_time_gone and v_target_fokus > 0);
end;
$$;

create or replace function public.get_daily_target_dashboard(
  p_user_id uuid,
  p_date date default current_date
)
returns table (
  period_id uuid,
  period_name text,
  active_week_number integer,
  active_week_start date,
  active_week_end date,
  working_days integer,
  target_weekly_all_type numeric,
  actual_weekly_all_type numeric,
  achievement_weekly_all_type_pct numeric,
  target_daily_all_type numeric,
  actual_daily_all_type numeric,
  achievement_daily_all_type_pct numeric,
  target_weekly_focus integer,
  actual_weekly_focus integer,
  achievement_weekly_focus_pct numeric,
  target_daily_focus numeric,
  actual_daily_focus integer,
  achievement_daily_focus_pct numeric
)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_period_id uuid;
  v_period_name text;
  v_period_start date;
  v_period_end date;
  v_week record;
  v_target_monthly_all numeric := 0;
  v_target_monthly_focus integer := 0;
  v_target_weekly_all numeric := 0;
  v_actual_weekly_all numeric := 0;
  v_target_daily_all numeric := 0;
  v_actual_daily_all numeric := 0;
  v_target_weekly_focus integer := 0;
  v_actual_weekly_focus integer := 0;
  v_target_daily_focus numeric := 0;
  v_actual_daily_focus integer := 0;
  v_target_fokus_detail jsonb := '{}'::jsonb;
  v_target_special_detail jsonb := '{}'::jsonb;
  v_effective_legacy_detail jsonb := '{}'::jsonb;
  v_effective_special_detail jsonb := '{}'::jsonb;
  v_has_focus_detail boolean := false;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  select
    tp.id,
    tp.period_name,
    tp.start_date,
    tp.end_date
  into
    v_period_id,
    v_period_name,
    v_period_start,
    v_period_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by
    case when tp.status = 'active' then 0 else 1 end,
    tp.start_date desc
  limit 1;

  if v_period_id is null then
    return;
  end if;

  select
    wt.week_number,
    (v_period_start + (wt.start_day - 1) * interval '1 day')::date as week_start,
    (v_period_start + (wt.end_day - 1) * interval '1 day')::date as week_end,
    wt.percentage
  into v_week
  from public.weekly_targets wt
  where coalesce(wt.period_id, v_period_id) = v_period_id
    and p_date between
      (v_period_start + (wt.start_day - 1) * interval '1 day')::date
      and
      (v_period_start + (wt.end_day - 1) * interval '1 day')::date
  order by
    case when wt.period_id = v_period_id then 0 else 1 end,
    wt.week_number
  limit 1;

  if v_week.week_number is null then
    return;
  end if;

  select
    coalesce(ut.target_sell_out, 0),
    coalesce(ut.target_fokus_total, 0),
    coalesce(ut.target_fokus_detail, '{}'::jsonb),
    coalesce(ut.target_special_detail, '{}'::jsonb)
  into
    v_target_monthly_all,
    v_target_monthly_focus,
    v_target_fokus_detail,
    v_target_special_detail
  from public.user_targets ut
  where ut.user_id = p_user_id
    and ut.period_id = v_period_id
  order by ut.updated_at desc
  limit 1;

  if v_target_special_detail <> '{}'::jsonb then
    v_effective_special_detail := v_target_special_detail;
    v_effective_legacy_detail := '{}'::jsonb;
  else
    v_effective_special_detail := '{}'::jsonb;
    v_effective_legacy_detail := v_target_fokus_detail;
  end if;

  v_has_focus_detail :=
    v_effective_legacy_detail <> '{}'::jsonb
    or v_effective_special_detail <> '{}'::jsonb;

  if v_target_monthly_focus <= 0 then
    v_target_monthly_focus := (
      coalesce((
        select sum((value::text)::numeric)
        from jsonb_each(v_effective_legacy_detail)
      ), 0)
      +
      coalesce((
        select sum((value::text)::numeric)
        from jsonb_each(v_effective_special_detail)
      ), 0)
    )::int;
  end if;

  v_target_weekly_all := round(v_target_monthly_all * coalesce(v_week.percentage, 0) / 100.0, 0);
  v_target_weekly_focus := round(v_target_monthly_focus * coalesce(v_week.percentage, 0) / 100.0);

  select coalesce(sum(sso.price_at_transaction), 0)
  into v_actual_weekly_all
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date between v_week.week_start and v_week.week_end
    and sso.deleted_at is null
    and coalesce(sso.is_chip_sale, false) = false;

  if v_has_focus_detail then
    select coalesce(count(*), 0)
    into v_actual_weekly_focus
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date between v_week.week_start and v_week.week_end
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
      and exists (
        select 1
        from public.get_target_focus_product_ids(
          v_period_id,
          v_effective_legacy_detail,
          v_effective_special_detail
        ) tp
        where tp.product_id = pv.product_id
      );
  else
    select coalesce(count(*), 0)
    into v_actual_weekly_focus
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    join public.products p on p.id = pv.product_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date between v_week.week_start and v_week.week_end
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
      and coalesce(p.is_focus, false) = true;
  end if;

  select coalesce(sum(sso.price_at_transaction), 0)
  into v_actual_daily_all
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date = p_date
    and sso.deleted_at is null
    and coalesce(sso.is_chip_sale, false) = false;

  if v_has_focus_detail then
    select coalesce(count(*), 0)
    into v_actual_daily_focus
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date = p_date
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
      and exists (
        select 1
        from public.get_target_focus_product_ids(
          v_period_id,
          v_effective_legacy_detail,
          v_effective_special_detail
        ) tp
        where tp.product_id = pv.product_id
      );
  else
    select coalesce(count(*), 0)
    into v_actual_daily_focus
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    join public.products p on p.id = pv.product_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date = p_date
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
      and coalesce(p.is_focus, false) = true;
  end if;

  v_target_daily_all := round(v_target_weekly_all / 6.0, 0);
  v_target_daily_focus := round(v_target_weekly_focus / 6.0, 2);

  return query
  select
    v_period_id,
    v_period_name,
    v_week.week_number,
    v_week.week_start,
    v_week.week_end,
    6,
    v_target_weekly_all,
    v_actual_weekly_all,
    case when v_target_weekly_all > 0 then round((v_actual_weekly_all / v_target_weekly_all) * 100, 2) else 0 end,
    v_target_daily_all,
    v_actual_daily_all,
    case when v_target_daily_all > 0 then round((v_actual_daily_all / v_target_daily_all) * 100, 2) else 0 end,
    v_target_weekly_focus,
    v_actual_weekly_focus,
    case when v_target_weekly_focus > 0 then round((v_actual_weekly_focus::numeric / v_target_weekly_focus::numeric) * 100, 2) else 0 end,
    v_target_daily_focus,
    v_actual_daily_focus,
    case when v_target_daily_focus > 0 then round((v_actual_daily_focus::numeric / v_target_daily_focus) * 100, 2) else 0 end;
end;
$$;
