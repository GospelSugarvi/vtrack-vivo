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

  v_special_rows := coalesce(
    public.get_promotor_special_rows_snapshot(
      p_user_id,
      p_period_id,
      v_week_start,
      case
        when v_is_future then v_week_start - 1
        else v_effective_end
      end,
      'weekly',
      v_week_percentage
    ),
    '[]'::jsonb
  );

  if v_elapsed_working_days > 0 then
    v_avg_per_day := round(v_actual_weekly_all / v_elapsed_working_days, 2);
  end if;

  if v_is_future then
    v_projected_weekly := 0;
  elsif v_is_active and v_elapsed_working_days > 0 then
    v_projected_weekly := round(v_avg_per_day * greatest(v_working_days, 1), 0);
  else
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
    'working_days', coalesce(v_working_days, 0),
    'elapsed_working_days', coalesce(v_elapsed_working_days, 0),
    'is_active', v_is_active,
    'is_future', v_is_future,
    'status_label', case
      when v_is_active then 'Minggu aktif'
      when v_is_future then 'Belum berjalan'
      else 'Selesai'
    end,
    'target_weekly_all_type', coalesce(v_target_weekly_all, 0),
    'actual_weekly_all_type', coalesce(v_actual_weekly_all, 0),
    'achievement_weekly_all_type_pct', case
      when v_target_weekly_all > 0 then round((v_actual_weekly_all / v_target_weekly_all) * 100, 2)
      else 0
    end,
    'target_weekly_focus', coalesce(v_target_weekly_focus, 0),
    'actual_weekly_focus', coalesce(v_actual_weekly_focus, 0),
    'achievement_weekly_focus_pct', case
      when v_target_weekly_focus > 0 then round((v_actual_weekly_focus::numeric / v_target_weekly_focus::numeric) * 100, 2)
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

create or replace function public.get_promotor_home_snapshot(
  p_user_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_daily jsonb := '{}'::jsonb;
  v_monthly jsonb := '{}'::jsonb;
  v_daily_bonus jsonb := '{}'::jsonb;
  v_weekly_bonus jsonb := '{}'::jsonb;
  v_monthly_bonus jsonb := '{}'::jsonb;
  v_daily_special jsonb := '[]'::jsonb;
  v_weekly_special jsonb := '[]'::jsonb;
  v_monthly_special jsonb := '[]'::jsonb;
  v_weekly_snapshots jsonb := '[]'::jsonb;
  v_yesterday jsonb := '{}'::jsonb;
  v_today_activity jsonb := '{}'::jsonb;
  v_period_id uuid;
  v_week_number int := 0;
  v_week_start date;
  v_week_end date;
  v_period_start date;
  v_period_end date;
  v_weekly_percentage numeric := 0;
  v_previous_month_omzet numeric := 0;
  v_vast_actual int := 0;
  v_vast_target int := 0;
  v_target_vast int := 0;
  v_yesterday_period_id uuid;
  v_clock_in_at timestamptz;
  v_has_absen boolean := false;
  v_has_sell_out boolean := false;
  v_has_stock boolean := false;
  v_has_promotion boolean := false;
  v_has_follower boolean := false;
  v_has_allbrand boolean := false;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  select to_jsonb(d.*)
  into v_daily
  from public.get_daily_target_dashboard(p_user_id, p_date) d
  limit 1;

  select to_jsonb(m.*)
  into v_monthly
  from public.get_target_dashboard(p_user_id, null) m
  limit 1;

  v_period_id := coalesce((v_daily->>'period_id')::uuid, (v_monthly->>'period_id')::uuid);
  v_week_number := coalesce((v_daily->>'active_week_number')::int, 0);
  v_week_start := nullif(v_daily->>'active_week_start', '')::date;
  v_week_end := nullif(v_daily->>'active_week_end', '')::date;
  v_period_start := coalesce(nullif(v_monthly->>'start_date', '')::date, date_trunc('month', p_date)::date);
  v_period_end := coalesce(nullif(v_monthly->>'end_date', '')::date, (date_trunc('month', p_date) + interval '1 month - 1 day')::date);

  if v_period_id is not null and v_week_number > 0 then
    select coalesce(wt.percentage, 0)
    into v_weekly_percentage
    from public.weekly_targets wt
    where wt.period_id = v_period_id
      and wt.week_number = v_week_number
    order by wt.week_number
    limit 1;
  end if;

  v_daily_bonus := public.get_promotor_bonus_snapshot_assembled(p_user_id, p_date, p_date);
  if v_week_start is not null and v_week_end is not null then
    v_weekly_bonus := public.get_promotor_bonus_snapshot_assembled(
      p_user_id,
      v_week_start,
      least(v_week_end, p_date)
    );
  end if;
  v_monthly_bonus := public.get_promotor_bonus_snapshot_assembled(
    p_user_id,
    v_period_start,
    least(v_period_end, p_date)
  );

  if v_period_id is not null then
    v_daily_special := public.get_promotor_special_rows_snapshot(
      p_user_id,
      v_period_id,
      p_date,
      p_date,
      'daily',
      0
    );
    if v_week_start is not null and v_week_end is not null then
      v_weekly_special := public.get_promotor_special_rows_snapshot(
        p_user_id,
        v_period_id,
        v_week_start,
        least(v_week_end, p_date),
        'weekly',
        v_weekly_percentage
      );
    end if;
    v_monthly_special := public.get_promotor_special_rows_snapshot(
      p_user_id,
      v_period_id,
      v_period_start,
      least(v_period_end, p_date),
      'monthly',
      0
    );

    with ranked_weeks as (
      select
        wt.week_number,
        row_number() over (
          partition by wt.week_number
          order by case when wt.period_id = v_period_id then 0 else 1 end, wt.week_number
        ) as rn
      from public.weekly_targets wt
      where coalesce(wt.period_id, v_period_id) = v_period_id
    ),
    selected_weeks as (
      select rw.week_number
      from ranked_weeks rw
      where rw.rn = 1
      order by rw.week_number
    )
    select coalesce(
      jsonb_agg(
        public.get_promotor_week_snapshot(
          p_user_id,
          v_period_id,
          sw.week_number,
          p_date
        )
        order by sw.week_number
      ),
      '[]'::jsonb
    )
    into v_weekly_snapshots
    from selected_weeks sw;
  end if;

  select coalesce(sum(sso.price_at_transaction), 0)
  into v_previous_month_omzet
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date between date_trunc('month', p_date - interval '1 month')::date
      and (date_trunc('month', p_date)::date - 1)
    and sso.deleted_at is null
    and coalesce(sso.is_chip_sale, false) = false;

  select to_jsonb(d.*)
  into v_yesterday
  from public.get_daily_target_dashboard(p_user_id, p_date - 1) d
  limit 1;

  v_yesterday_period_id := nullif(v_yesterday->>'period_id', '')::uuid;
  select count(*)::int
  into v_vast_actual
  from public.sales_sell_out sso
  where sso.promotor_id = p_user_id
    and sso.transaction_date = p_date - 1
    and sso.deleted_at is null
    and (
      sso.leasing_provider = 'VAST'
      or sso.leasing_provider = 'VAST Finance'
    );

  if v_yesterday_period_id is not null then
    select coalesce(ut.target_vast, 0)
    into v_target_vast
    from public.user_targets ut
    where ut.user_id = p_user_id
      and ut.period_id = v_yesterday_period_id
    order by ut.updated_at desc
    limit 1;

    if v_target_vast > 0 then
      v_vast_target := ceil(
        v_target_vast::numeric /
        extract(day from (date_trunc('month', p_date - 1) + interval '1 month - 1 day'))::numeric
      );
    end if;
  end if;

  select min(a.created_at)
  into v_clock_in_at
  from public.attendance a
  where a.user_id = p_user_id
    and a.created_at >= p_date::timestamp
    and a.created_at < (p_date + 1)::timestamp;

  v_has_absen := v_clock_in_at is not null;

  select exists(
    select 1 from public.sales_sell_out sso
    where sso.promotor_id = p_user_id
      and sso.transaction_date = p_date
      and sso.deleted_at is null
  ) into v_has_sell_out;

  select exists(
    select 1 from public.stock_movement_log sml
    where sml.moved_by = p_user_id
      and sml.movement_type in ('initial', 'transfer_in', 'adjustment')
      and sml.moved_at >= p_date::timestamp
      and sml.moved_at < (p_date + 1)::timestamp
  ) or exists(
    select 1 from public.stock_validations sv
    where sv.promotor_id = p_user_id
      and sv.validation_date >= p_date::timestamp
      and sv.validation_date < (p_date + 1)::timestamp
  ) into v_has_stock;

  select exists(
    select 1 from public.promotion_reports pr
    where pr.promotor_id = p_user_id
      and pr.created_at >= p_date::timestamp
      and pr.created_at < (p_date + 1)::timestamp
  ) into v_has_promotion;

  select exists(
    select 1 from public.follower_reports fr
    where fr.promotor_id = p_user_id
      and fr.created_at >= p_date::timestamp
      and fr.created_at < (p_date + 1)::timestamp
  ) into v_has_follower;

  select exists(
    select 1 from public.allbrand_reports ar
    where ar.promotor_id = p_user_id
      and ar.report_date = p_date
  ) into v_has_allbrand;

  v_today_activity := jsonb_build_object(
    'absen', v_has_absen,
    'sell_out', v_has_sell_out,
    'stock', v_has_stock,
    'promotion', v_has_promotion,
    'follower', v_has_follower,
    'allbrand', v_has_allbrand,
    'completed_count',
      (case when v_has_absen then 1 else 0 end)
      + (case when v_has_sell_out then 1 else 0 end)
      + (case when v_has_stock then 1 else 0 end)
      + (case when v_has_promotion then 1 else 0 end)
      + (case when v_has_follower then 1 else 0 end)
      + (case when v_has_allbrand then 1 else 0 end),
    'total_count', 6
  );

  return jsonb_build_object(
    'daily_target', coalesce(v_daily, '{}'::jsonb),
    'monthly_target', coalesce(v_monthly, '{}'::jsonb),
    'active_week_number', v_week_number,
    'daily_bonus', coalesce(v_daily_bonus, '{}'::jsonb),
    'weekly_bonus', coalesce(v_weekly_bonus, '{}'::jsonb),
    'monthly_bonus', coalesce(v_monthly_bonus, '{}'::jsonb),
    'weekly_snapshots', coalesce(v_weekly_snapshots, '[]'::jsonb),
    'daily_special_rows', coalesce(v_daily_special, '[]'::jsonb),
    'weekly_special_rows', coalesce(v_weekly_special, '[]'::jsonb),
    'monthly_special_rows', coalesce(v_monthly_special, '[]'::jsonb),
    'previous_month_omzet', coalesce(v_previous_month_omzet, 0),
    'yesterday_achievement', jsonb_build_object(
      'all_type_actual', coalesce((v_yesterday->>'actual_daily_all_type')::numeric, 0),
      'all_type_target', coalesce((v_yesterday->>'target_daily_all_type')::numeric, 0),
      'focus_actual', coalesce((v_yesterday->>'actual_daily_focus')::numeric, 0),
      'focus_target', coalesce((v_yesterday->>'target_daily_focus')::numeric, 0),
      'vast_actual', v_vast_actual,
      'vast_target', v_vast_target
    ),
    'today_activity', v_today_activity,
    'clock_in_today', v_has_absen,
    'clock_in_time', case
      when v_clock_in_at is null then null
      else to_char(timezone('Asia/Makassar', v_clock_in_at), 'HH24:MI')
    end
  );
end;
$$;

grant execute on function public.get_promotor_week_snapshot(uuid, uuid, integer, date) to authenticated;
grant execute on function public.get_promotor_home_snapshot(uuid, date) to authenticated;
