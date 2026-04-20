create or replace function public.get_effective_workday_count(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_count integer := 0;
begin
  if p_user_id is null or p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    return 0;
  end if;

  select count(*)::int
  into v_count
  from public.schedules s
  where s.promotor_id = p_user_id
    and s.schedule_date between p_start_date and p_end_date
    and coalesce(s.shift_type, 'libur') <> 'libur'
    and coalesce(s.status, 'draft') in ('approved', 'submitted', 'draft');

  if coalesce(v_count, 0) > 0 then
    return v_count;
  end if;

  select count(*)::int
  into v_count
  from generate_series(p_start_date, p_end_date, interval '1 day') gs(d)
  where extract(isodow from gs.d) < 7;

  return coalesce(v_count, 0);
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
  v_actual_monthly_all_before numeric := 0;
  v_actual_monthly_focus_before integer := 0;
  v_remaining_workdays integer := 0;
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
  order by tp.start_date desc, tp.created_at desc
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
    coalesce(ut.target_omzet, 0),
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
      and p.is_focus = true;
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
      and p.is_focus = true;
  end if;

  select coalesce(sum(sso.price_at_transaction), 0)
  into v_actual_monthly_all_before
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date between v_period_start and (p_date - 1)
    and sso.deleted_at is null
    and coalesce(sso.is_chip_sale, false) = false;

  if v_has_focus_detail then
    select coalesce(count(*), 0)
    into v_actual_monthly_focus_before
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date between v_period_start and (p_date - 1)
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
    into v_actual_monthly_focus_before
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    join public.products p on p.id = pv.product_id
    where sso.promotor_id = p_user_id
      and sso.transaction_date between v_period_start and (p_date - 1)
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
      and p.is_focus = true;
  end if;

  v_remaining_workdays := public.get_effective_workday_count(
    p_user_id,
    p_date,
    v_period_end
  );

  v_target_daily_all := case
    when v_remaining_workdays > 0
      then round(greatest(v_target_monthly_all - v_actual_monthly_all_before, 0) / v_remaining_workdays::numeric, 0)
    else 0
  end;
  v_target_daily_focus := case
    when v_remaining_workdays > 0
      then round(greatest(v_target_monthly_focus - v_actual_monthly_focus_before, 0) / v_remaining_workdays::numeric, 2)
    else 0
  end;

  return query
  select
    v_period_id,
    v_period_name,
    v_week.week_number,
    v_week.week_start,
    v_week.week_end,
    v_remaining_workdays,
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
