create or replace function public.get_daily_target_dashboard(
  p_user_id uuid,
  p_date date default current_date
)
returns table(
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
    coalesce(ut.target_fokus_total, 0)
  into
    v_target_monthly_all,
    v_target_monthly_focus
  from public.user_targets ut
  where ut.user_id = p_user_id
    and ut.period_id = v_period_id
  order by ut.updated_at desc
  limit 1;

  v_target_weekly_all := round(v_target_monthly_all * coalesce(v_week.percentage, 0) / 100.0, 0);
  v_target_weekly_focus := round(v_target_monthly_focus * coalesce(v_week.percentage, 0) / 100.0);

  select coalesce(sum(sso.price_at_transaction), 0)
  into v_actual_weekly_all
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date between v_week.week_start and v_week.week_end
    and sso.deleted_at is null
    and coalesce(sso.is_chip_sale, false) = false;

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

  select coalesce(sum(sso.price_at_transaction), 0)
  into v_actual_daily_all
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date = p_date
    and sso.deleted_at is null
    and coalesce(sso.is_chip_sale, false) = false;

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

create or replace function public.get_target_dashboard(
  p_user_id uuid,
  p_period_id uuid default null
)
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
as $$
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
$$;
