create or replace function public.get_sator_home_weekly_snapshots(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_period_id uuid;
  v_start date;
  v_end date;
  v_target_sellout numeric := 0;
  v_target_fokus numeric := 0;
  v_active_week_number integer := 0;
  v_weekly_snapshots jsonb := '[]'::jsonb;
  v_week record;
  v_week_start date;
  v_week_end date;
  v_working_days integer := 0;
  v_elapsed_working_days integer := 0;
  v_actual_omzet numeric := 0;
  v_actual_fokus integer := 0;
  v_week_promotors jsonb := '[]'::jsonb;
begin
  if p_sator_id is null then
    raise exception 'p_sator_id is required';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is null then
    return jsonb_build_object(
      'active_week_number', 0,
      'weekly_snapshots', '[]'::jsonb
    );
  end if;

  select
    coalesce(ut.target_sell_out, 0),
    coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)
  into v_target_sellout, v_target_fokus
  from public.user_targets ut
  where ut.user_id = p_sator_id
    and ut.period_id = v_period_id
  order by ut.updated_at desc nulls last
  limit 1;

  select coalesce(wt.week_number, 0)
  into v_active_week_number
  from public.weekly_targets wt
  where wt.period_id = v_period_id
    and extract(day from p_date)::int between wt.start_day and wt.end_day
  order by wt.week_number
  limit 1;

  if v_active_week_number = 0 then
    v_active_week_number := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);
  end if;

  for v_week in
    select
      gs.week_number,
      coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
      coalesce(
        wt.end_day,
        case
          when gs.week_number < 4 then gs.week_number * 7
          else extract(day from v_end)::int
        end
      ) as end_day,
      coalesce(wt.percentage, 25) as percentage
    from generate_series(1, 4) as gs(week_number)
    left join public.weekly_targets wt
      on wt.period_id = v_period_id
     and wt.week_number = gs.week_number
    order by gs.week_number
  loop
    v_week_start := greatest(v_start, v_start + (v_week.start_day - 1));
    v_week_end := least(v_end, v_start + (v_week.end_day - 1));

    select count(*)::int
    into v_working_days
    from generate_series(v_week_start, v_week_end, interval '1 day') as day_ref
    where extract(isodow from day_ref)::int < 7;

    if p_date < v_week_start then
      v_elapsed_working_days := 0;
    else
      select count(*)::int
      into v_elapsed_working_days
      from generate_series(
        v_week_start,
        least(v_week_end, p_date),
        interval '1 day'
      ) as day_ref
      where extract(isodow from day_ref)::int < 7;
    end if;

    select
      coalesce(sum(s.price_at_transaction), 0),
      coalesce(sum(case when coalesce(p.is_focus, false) or coalesce(p.is_fokus, false) then 1 else 0 end), 0)
    into v_actual_omzet, v_actual_fokus
    from public.sales_sell_out s
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = s.promotor_id
     and hsp.sator_id = p_sator_id
     and hsp.active = true
    left join public.product_variants pv on pv.id = s.variant_id
    left join public.products p on p.id = pv.product_id
    where s.transaction_date between v_week_start and least(v_week_end, p_date)
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false;

    with promotor_scope as (
      select
        u.id as promotor_id,
        coalesce(u.full_name, 'Promotor') as full_name,
        coalesce(ut.target_sell_out, 0)::numeric as target_sell_out,
        coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)::numeric as target_fokus_total
      from public.hierarchy_sator_promotor hsp
      join public.users u on u.id = hsp.promotor_id
      left join public.user_targets ut
        on ut.user_id = u.id
       and ut.period_id = v_period_id
      where hsp.sator_id = p_sator_id
        and hsp.active = true
        and u.deleted_at is null
    ),
    latest_assignments as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        coalesce(st.store_name, '-') as store_name
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      where aps.active = true
      order by aps.promotor_id, aps.created_at desc nulls last
    ),
    promotor_sales as (
      select
        s.promotor_id,
        coalesce(sum(s.price_at_transaction), 0)::numeric as actual_nominal,
        coalesce(sum(case when coalesce(p.is_focus, false) or coalesce(p.is_fokus, false) then 1 else 0 end), 0)::numeric as actual_focus_units
      from public.sales_sell_out s
      left join public.product_variants pv on pv.id = s.variant_id
      left join public.products p on p.id = pv.product_id
      where s.transaction_date between v_week_start and least(v_week_end, p_date)
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false
      group by s.promotor_id
    )
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'promotor_id', ps.promotor_id,
          'name', ps.full_name,
          'store_name', coalesce(la.store_name, '-'),
          'target_nominal', round(ps.target_sell_out * v_week.percentage / 100.0),
          'actual_nominal', round(coalesce(sales.actual_nominal, 0)),
          'target_focus_units', round(ps.target_fokus_total * v_week.percentage / 100.0),
          'actual_focus_units', round(coalesce(sales.actual_focus_units, 0)),
          'achievement_pct', case
            when ps.target_sell_out * v_week.percentage / 100.0 > 0
              then round((coalesce(sales.actual_nominal, 0) / (ps.target_sell_out * v_week.percentage / 100.0)) * 100.0, 1)
            else 0
          end,
          'underperform', case
            when ps.target_sell_out * v_week.percentage / 100.0 > 0
              then ((coalesce(sales.actual_nominal, 0) / (ps.target_sell_out * v_week.percentage / 100.0)) * 100.0) < 60
            else false
          end
        )
        order by coalesce(sales.actual_nominal, 0) desc, ps.full_name
      ),
      '[]'::jsonb
    )
    into v_week_promotors
    from promotor_scope ps
    left join latest_assignments la on la.promotor_id = ps.promotor_id
    left join promotor_sales sales on sales.promotor_id = ps.promotor_id;

    v_weekly_snapshots := v_weekly_snapshots || jsonb_build_array(
      jsonb_build_object(
        'week_number', v_week.week_number,
        'start_date', v_week_start,
        'end_date', v_week_end,
        'percentage_of_total', v_week.percentage,
        'is_active', v_week.week_number = v_active_week_number,
        'is_future', v_week_start > p_date,
        'status_label', case
          when v_week_start > p_date then 'Belum berjalan'
          when v_week.week_number = v_active_week_number then 'Minggu aktif'
          else 'Riwayat minggu'
        end,
        'working_days', v_working_days,
        'elapsed_working_days', v_elapsed_working_days,
        'summary', jsonb_build_object(
          'week_index', v_week.week_number,
          'week_start', v_week_start,
          'week_end', v_week_end,
          'week_pct', v_week.percentage,
          'target_omzet', round(v_target_sellout * v_week.percentage / 100.0),
          'actual_omzet', round(v_actual_omzet),
          'target_fokus', round(v_target_fokus * v_week.percentage / 100.0),
          'actual_fokus', v_actual_fokus,
          'reports_pending', 0
        ),
        'promotors', coalesce(v_week_promotors, '[]'::jsonb)
      )
    );
  end loop;

  return jsonb_build_object(
    'active_week_number', v_active_week_number,
    'weekly_snapshots', coalesce(v_weekly_snapshots, '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_spv_home_weekly_snapshots(
  p_spv_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_period_id uuid;
  v_start date;
  v_end date;
  v_active_week_number integer := 0;
  v_team_target_sell_out_monthly numeric := 0;
  v_team_target_focus_monthly numeric := 0;
  v_weekly_snapshots jsonb := '[]'::jsonb;
  v_week record;
  v_week_start date;
  v_week_end date;
  v_working_days integer := 0;
  v_elapsed_working_days integer := 0;
  v_actual_omzet numeric := 0;
  v_actual_focus integer := 0;
  v_sator_cards jsonb := '[]'::jsonb;
begin
  if p_spv_id is null then
    raise exception 'p_spv_id is required';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_period_id is null then
    return jsonb_build_object(
      'active_week_number', 0,
      'weekly_snapshots', '[]'::jsonb
    );
  end if;

  select coalesce(wt.week_number, 0)
  into v_active_week_number
  from public.weekly_targets wt
  where wt.period_id = v_period_id
    and extract(day from p_date)::int between wt.start_day and wt.end_day
  order by wt.week_number
  limit 1;

  if v_active_week_number = 0 then
    v_active_week_number := greatest(least(((extract(day from p_date)::int - 1) / 7)::int + 1, 4), 1);
  end if;

  select
    coalesce(ut.target_sell_out, 0),
    coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)
  into v_team_target_sell_out_monthly, v_team_target_focus_monthly
  from public.user_targets ut
  where ut.user_id = p_spv_id
    and ut.period_id = v_period_id
  order by ut.updated_at desc nulls last
  limit 1;

  if coalesce(v_team_target_sell_out_monthly, 0) = 0 or coalesce(v_team_target_focus_monthly, 0) = 0 then
    with sator_scope as (
      select hss.sator_id
      from public.hierarchy_spv_sator hss
      where hss.spv_id = p_spv_id
        and hss.active = true
    )
    select
      case
        when coalesce(v_team_target_sell_out_monthly, 0) > 0 then v_team_target_sell_out_monthly
        else coalesce(sum(ut.target_sell_out), 0)
      end,
      case
        when coalesce(v_team_target_focus_monthly, 0) > 0 then v_team_target_focus_monthly
        else coalesce(sum(coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)), 0)
      end
    into v_team_target_sell_out_monthly, v_team_target_focus_monthly
    from public.user_targets ut
    join sator_scope ss on ss.sator_id = ut.user_id
    where ut.period_id = v_period_id;
  end if;

  for v_week in
    select
      gs.week_number,
      coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
      coalesce(
        wt.end_day,
        case
          when gs.week_number < 4 then gs.week_number * 7
          else extract(day from v_end)::int
        end
      ) as end_day,
      coalesce(wt.percentage, 25) as percentage
    from generate_series(1, 4) as gs(week_number)
    left join public.weekly_targets wt
      on wt.period_id = v_period_id
     and wt.week_number = gs.week_number
    order by gs.week_number
  loop
    v_week_start := greatest(v_start, v_start + (v_week.start_day - 1));
    v_week_end := least(v_end, v_start + (v_week.end_day - 1));

    select count(*)::int
    into v_working_days
    from generate_series(v_week_start, v_week_end, interval '1 day') as day_ref
    where extract(isodow from day_ref)::int < 7;

    if p_date < v_week_start then
      v_elapsed_working_days := 0;
    else
      select count(*)::int
      into v_elapsed_working_days
      from generate_series(
        v_week_start,
        least(v_week_end, p_date),
        interval '1 day'
      ) as day_ref
      where extract(isodow from day_ref)::int < 7;
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
      coalesce(sum(s.price_at_transaction), 0),
      coalesce(sum(case when coalesce(p.is_focus, false) or coalesce(p.is_fokus, false) then 1 else 0 end), 0)
    into v_actual_omzet, v_actual_focus
    from public.sales_sell_out s
    join promotor_scope ps on ps.promotor_id = s.promotor_id
    left join public.product_variants pv on pv.id = s.variant_id
    left join public.products p on p.id = pv.product_id
    where s.transaction_date between v_week_start and least(v_week_end, p_date)
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false;

    with sator_scope as (
      select
        u.id as sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name,
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
    ),
    sator_targets as (
      select
        ss.sator_id,
        coalesce(ut.target_sell_out, 0)::numeric as target_sell_out,
        coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)::numeric as target_fokus_total
      from sator_scope ss
      left join public.user_targets ut
        on ut.user_id = ss.sator_id
       and ut.period_id = v_period_id
    ),
    sales_by_sator as (
      select
        hsp.sator_id,
        coalesce(sum(s.price_at_transaction), 0)::numeric as actual_sell_out,
        coalesce(sum(case when coalesce(p.is_focus, false) or coalesce(p.is_fokus, false) then 1 else 0 end), 0)::int as actual_focus
      from public.sales_sell_out s
      join public.hierarchy_sator_promotor hsp
        on hsp.promotor_id = s.promotor_id
       and hsp.active = true
      left join public.product_variants pv on pv.id = s.variant_id
      left join public.products p on p.id = pv.product_id
      join sator_scope ss on ss.sator_id = hsp.sator_id
      where s.transaction_date between v_week_start and least(v_week_end, p_date)
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false
      group by hsp.sator_id
    ),
    top_promotor_sales as (
      select
        hsp.sator_id,
        coalesce(u.full_name, 'Promotor') as promotor_name,
        count(*)::int as units,
        row_number() over (
          partition by hsp.sator_id
          order by count(*) desc, coalesce(u.full_name, 'Promotor')
        ) as rn
      from public.sales_sell_out s
      join public.hierarchy_sator_promotor hsp
        on hsp.promotor_id = s.promotor_id
       and hsp.active = true
      join sator_scope ss on ss.sator_id = hsp.sator_id
      join public.users u on u.id = s.promotor_id
      where s.transaction_date between v_week_start and least(v_week_end, p_date)
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false
      group by hsp.sator_id, u.full_name
    ),
    top_promotors as (
      select
        tps.sator_id,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'name', tps.promotor_name,
              'units', tps.units
            )
            order by tps.units desc, tps.promotor_name
          ),
          '[]'::jsonb
        ) as rows
      from top_promotor_sales tps
      where tps.rn <= 3
      group by tps.sator_id
    )
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sator_id', ss.sator_id,
          'sator_name', ss.sator_name,
          'sator_area', ss.sator_area,
          'promotor_count', coalesce(pc.promotor_count, 0),
          'target_sell_out_weekly', round(coalesce(st.target_sell_out, 0) * v_week.percentage / 100.0),
          'actual_sell_out_weekly', round(coalesce(sbs.actual_sell_out, 0)),
          'target_focus_weekly', round(coalesce(st.target_fokus_total, 0) * v_week.percentage / 100.0),
          'actual_focus_weekly', coalesce(sbs.actual_focus, 0),
          'top_promotors', coalesce(tp.rows, '[]'::jsonb)
        )
        order by coalesce(sbs.actual_sell_out, 0) desc, ss.sator_name
      ),
      '[]'::jsonb
    )
    into v_sator_cards
    from sator_scope ss
    left join promotor_counts pc on pc.sator_id = ss.sator_id
    left join sator_targets st on st.sator_id = ss.sator_id
    left join sales_by_sator sbs on sbs.sator_id = ss.sator_id
    left join top_promotors tp on tp.sator_id = ss.sator_id;

    v_weekly_snapshots := v_weekly_snapshots || jsonb_build_array(
      jsonb_build_object(
        'week_number', v_week.week_number,
        'start_date', v_week_start,
        'end_date', v_week_end,
        'percentage_of_total', v_week.percentage,
        'is_active', v_week.week_number = v_active_week_number,
        'is_future', v_week_start > p_date,
        'status_label', case
          when v_week_start > p_date then 'Belum berjalan'
          when v_week.week_number = v_active_week_number then 'Minggu aktif'
          else 'Riwayat minggu'
        end,
        'working_days', v_working_days,
        'elapsed_working_days', v_elapsed_working_days,
        'summary', jsonb_build_object(
          'target_sell_out_weekly', round(v_team_target_sell_out_monthly * v_week.percentage / 100.0),
          'target_focus_weekly', round(v_team_target_focus_monthly * v_week.percentage / 100.0),
          'actual_sell_out_weekly', round(v_actual_omzet),
          'actual_focus_weekly', v_actual_focus
        ),
        'sator_cards', coalesce(v_sator_cards, '[]'::jsonb)
      )
    );
  end loop;

  return jsonb_build_object(
    'active_week_number', v_active_week_number,
    'weekly_snapshots', coalesce(v_weekly_snapshots, '[]'::jsonb)
  );
end;
$$;
