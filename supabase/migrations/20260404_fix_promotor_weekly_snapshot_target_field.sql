create or replace function public.get_promotor_week_snapshot(
  p_user_id uuid,
  p_period_id uuid,
  p_week_number integer,
  p_cutoff_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_period_name text;
  v_period_start date;
  v_period_end date;
  v_week_start date;
  v_week_end date;
  v_week_percentage numeric := 0;
  v_target_monthly_all numeric := 0;
  v_target_monthly_focus integer := 0;
  v_target_weekly_all numeric := 0;
  v_actual_weekly_all numeric := 0;
  v_target_weekly_focus integer := 0;
  v_actual_weekly_focus integer := 0;
  v_target_fokus_detail jsonb := '{}'::jsonb;
  v_target_special_detail jsonb := '{}'::jsonb;
  v_effective_legacy_detail jsonb := '{}'::jsonb;
  v_effective_special_detail jsonb := '{}'::jsonb;
  v_has_focus_detail boolean := false;
  v_working_days integer := 0;
  v_elapsed_working_days integer := 0;
  v_effective_end date;
  v_is_active boolean := false;
  v_is_future boolean := false;
  v_avg_per_day numeric := 0;
  v_projected_weekly numeric := 0;
  v_weekly_gap numeric := 0;
  v_bonus jsonb := '{}'::jsonb;
  v_special_rows jsonb := '[]'::jsonb;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  if p_period_id is null then
    raise exception 'p_period_id is required';
  end if;

  if p_week_number is null then
    raise exception 'p_week_number is required';
  end if;

  select
    tp.period_name,
    tp.start_date,
    tp.end_date
  into
    v_period_name,
    v_period_start,
    v_period_end
  from public.target_periods tp
  where tp.id = p_period_id
    and tp.deleted_at is null
  limit 1;

  if v_period_start is null then
    return '{}'::jsonb;
  end if;

  with ranked_weeks as (
    select
      wt.week_number,
      wt.start_day,
      wt.end_day,
      coalesce(wt.percentage, 0) as percentage,
      row_number() over (
        partition by wt.week_number
        order by case when wt.period_id = p_period_id then 0 else 1 end, wt.week_number
      ) as rn
    from public.weekly_targets wt
    where coalesce(wt.period_id, p_period_id) = p_period_id
  )
  select
    (v_period_start + (rw.start_day - 1) * interval '1 day')::date,
    (v_period_start + (rw.end_day - 1) * interval '1 day')::date,
    rw.percentage
  into
    v_week_start,
    v_week_end,
    v_week_percentage
  from ranked_weeks rw
  where rw.week_number = p_week_number
    and rw.rn = 1
  limit 1;

  if v_week_start is null or v_week_end is null then
    return '{}'::jsonb;
  end if;

  v_is_active := p_cutoff_date between v_week_start and v_week_end;
  v_is_future := p_cutoff_date < v_week_start;
  v_effective_end := case
    when v_is_future then v_week_start - 1
    else least(v_week_end, p_cutoff_date)
  end;

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

  v_target_weekly_all := round(v_target_monthly_all * v_week_percentage / 100.0, 0);
  v_target_weekly_focus := round(v_target_monthly_focus * v_week_percentage / 100.0);

  select count(*)::int
  into v_working_days
  from generate_series(v_week_start, v_week_end, interval '1 day') gs(d)
  where extract(isodow from gs.d) < 7;

  if not v_is_future then
    select count(*)::int
    into v_elapsed_working_days
    from generate_series(v_week_start, v_effective_end, interval '1 day') gs(d)
    where extract(isodow from gs.d) < 7;

    select coalesce(sum(sso.price_at_transaction), 0)
    into v_actual_weekly_all
    from public.sales_sell_out sso
    where sso.promotor_id = p_user_id
      and sso.transaction_date between v_week_start and v_effective_end
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false;

    if v_has_focus_detail then
      select coalesce(count(*), 0)
      into v_actual_weekly_focus
      from public.sales_sell_out sso
      join public.product_variants pv on pv.id = sso.variant_id
      where sso.promotor_id = p_user_id
        and sso.transaction_date between v_week_start and v_effective_end
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
      select coalesce(count(*), 0)
      into v_actual_weekly_focus
      from public.sales_sell_out sso
      join public.product_variants pv on pv.id = sso.variant_id
      join public.products p on p.id = pv.product_id
      where sso.promotor_id = p_user_id
        and sso.transaction_date between v_week_start and v_effective_end
        and sso.deleted_at is null
        and coalesce(sso.is_chip_sale, false) = false
        and coalesce(p.is_focus, false) = true;
    end if;
  end if;

  if v_is_future then
    v_bonus := jsonb_build_object(
      'promotor_id', p_user_id,
      'period_start', v_week_start,
      'period_end', v_week_end,
      'event_count', 0,
      'total_sales', 0,
      'total_revenue', 0,
      'total_bonus', 0,
      'by_bonus_type', '{}'::jsonb
    );
  else
    v_bonus := coalesce(
      public.get_promotor_bonus_snapshot_assembled(
        p_user_id,
        v_week_start,
        v_effective_end
      ),
      '{}'::jsonb
    );
  end if;

  v_special_rows := public.get_promotor_special_rows_snapshot(
    p_user_id,
    p_period_id,
    v_week_start,
    least(v_week_end, p_cutoff_date),
    'weekly',
    v_week_percentage
  );

  if v_elapsed_working_days <= 0 then
    v_avg_per_day := 0;
    v_projected_weekly := 0;
  elsif v_elapsed_working_days < v_working_days then
    v_avg_per_day := round(v_actual_weekly_all / greatest(v_elapsed_working_days, 1), 0);
    v_projected_weekly := round(v_avg_per_day * greatest(v_working_days, 1), 0);
  else
    v_avg_per_day := round(v_actual_weekly_all / greatest(v_working_days, 1), 0);
    v_projected_weekly := v_actual_weekly_all;
  end if;

  v_weekly_gap := greatest(v_target_weekly_all - v_actual_weekly_all, 0);

  return jsonb_build_object(
    'period_id', p_period_id,
    'period_name', v_period_name,
    'week_number', p_week_number,
    'label', format('Minggu %s', p_week_number),
    'start_date', v_week_start,
    'end_date', v_week_end,
    'effective_end_date', case when v_is_future then null else v_effective_end end,
    'percentage_of_total', v_week_percentage,
    'is_active', v_is_active,
    'is_future', v_is_future,
    'status_label', case
      when v_is_future then 'Belum berjalan'
      when v_is_active then 'Minggu aktif'
      else 'Riwayat minggu'
    end,
    'working_days', v_working_days,
    'elapsed_working_days', v_elapsed_working_days,
    'target_weekly_all_type', coalesce(v_target_weekly_all, 0),
    'actual_weekly_all_type', coalesce(v_actual_weekly_all, 0),
    'achievement_weekly_all_type_pct', case
      when coalesce(v_target_weekly_all, 0) > 0
        then round((coalesce(v_actual_weekly_all, 0) / v_target_weekly_all) * 100.0, 1)
      else 0
    end,
    'target_weekly_focus', coalesce(v_target_weekly_focus, 0),
    'actual_weekly_focus', coalesce(v_actual_weekly_focus, 0),
    'achievement_weekly_focus_pct', case
      when coalesce(v_target_weekly_focus, 0) > 0
        then round((coalesce(v_actual_weekly_focus, 0)::numeric / v_target_weekly_focus::numeric) * 100.0, 1)
      else 0
    end,
    'avg_per_day', coalesce(v_avg_per_day, 0),
    'projected_weekly', coalesce(v_projected_weekly, 0),
    'weekly_gap', coalesce(v_weekly_gap, 0),
    'bonus', coalesce(v_bonus, '{}'::jsonb),
    'special_rows', coalesce(v_special_rows, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_promotor_week_snapshot(uuid, uuid, integer, date) to authenticated;
