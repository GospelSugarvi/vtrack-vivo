create or replace function public.get_promotor_sellout_insight(
  p_user_id uuid,
  p_start_date date default null,
  p_end_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_end_date date := coalesce(p_end_date, current_date);
  v_start_date date := coalesce(
    p_start_date,
    date_trunc('month', coalesce(p_end_date, current_date))::date
  );
  v_current_period_id uuid;
  v_current_period_start date;
  v_current_period_end date;
  v_current_week_number integer := 0;
  v_current_week_start date;
  v_current_week_end date;
  v_prev_week_start date;
  v_prev_week_end date;
begin
  if v_start_date > v_end_date then
    v_start_date := v_end_date;
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_current_period_id, v_current_period_start, v_current_period_end
  from public.target_periods tp
  where v_end_date between tp.start_date and tp.end_date
    and tp.deleted_at is null
  order by tp.start_date desc, tp.created_at desc
  limit 1;

  if v_current_period_id is not null then
    with week_rows as (
      select
        gs.week_number,
        coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
        coalesce(
          wt.end_day,
          case
            when gs.week_number < 4 then gs.week_number * 7
            else extract(day from v_current_period_end)::int
          end
        ) as end_day
      from generate_series(1, 4) as gs(week_number)
      left join public.weekly_targets wt
        on wt.period_id = v_current_period_id
       and wt.week_number = gs.week_number
    )
    select
      wr.week_number,
      greatest(
        v_current_period_start,
        (v_current_period_start + (wr.start_day - 1) * interval '1 day')::date
      ),
      least(
        v_current_period_end,
        (v_current_period_start + (wr.end_day - 1) * interval '1 day')::date
      )
    into
      v_current_week_number,
      v_current_week_start,
      v_current_week_end
    from week_rows wr
    where extract(day from v_end_date)::int between wr.start_day and wr.end_day
    order by wr.week_number
    limit 1;

    if v_current_week_start is null then
      with week_rows as (
        select
          gs.week_number,
          coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
          coalesce(
            wt.end_day,
            case
              when gs.week_number < 4 then gs.week_number * 7
              else extract(day from v_current_period_end)::int
            end
          ) as end_day
        from generate_series(1, 4) as gs(week_number)
        left join public.weekly_targets wt
          on wt.period_id = v_current_period_id
         and wt.week_number = gs.week_number
      )
      select
        wr.week_number,
        greatest(
          v_current_period_start,
          (v_current_period_start + (wr.start_day - 1) * interval '1 day')::date
        ),
        least(
          v_current_period_end,
          (v_current_period_start + (wr.end_day - 1) * interval '1 day')::date
        )
      into
        v_current_week_number,
        v_current_week_start,
        v_current_week_end
      from week_rows wr
      where wr.week_number = greatest(least(((extract(day from v_end_date)::int - 1) / 7)::int + 1, 4), 1)
      limit 1;
    end if;

    if v_current_week_number > 1 then
      with week_rows as (
        select
          gs.week_number,
          coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
          coalesce(
            wt.end_day,
            case
              when gs.week_number < 4 then gs.week_number * 7
              else extract(day from v_current_period_end)::int
            end
          ) as end_day
        from generate_series(1, 4) as gs(week_number)
        left join public.weekly_targets wt
          on wt.period_id = v_current_period_id
         and wt.week_number = gs.week_number
      )
      select
        greatest(
          v_current_period_start,
          (v_current_period_start + (wr.start_day - 1) * interval '1 day')::date
        ),
        least(
          v_current_period_end,
          (v_current_period_start + (wr.end_day - 1) * interval '1 day')::date
        )
      into v_prev_week_start, v_prev_week_end
      from week_rows wr
      where wr.week_number = v_current_week_number - 1
      limit 1;
    else
      with prev_period as (
        select tp.id, tp.start_date, tp.end_date
        from public.target_periods tp
        where tp.end_date < v_current_period_start
          and tp.deleted_at is null
        order by tp.end_date desc, tp.created_at desc
        limit 1
      ),
      week_rows as (
        select
          pp.start_date,
          pp.end_date,
          gs.week_number,
          coalesce(wt.start_day, ((gs.week_number - 1) * 7) + 1) as start_day,
          coalesce(
            wt.end_day,
            case
              when gs.week_number < 4 then gs.week_number * 7
              else extract(day from pp.end_date)::int
            end
          ) as end_day
        from prev_period pp
        cross join generate_series(1, 4) as gs(week_number)
        left join public.weekly_targets wt
          on wt.period_id = pp.id
         and wt.week_number = gs.week_number
      )
      select
        greatest(
          wr.start_date,
          (wr.start_date + (wr.start_day - 1) * interval '1 day')::date
        ),
        least(
          wr.end_date,
          (wr.start_date + (wr.end_day - 1) * interval '1 day')::date
        )
      into v_prev_week_start, v_prev_week_end
      from week_rows wr
      order by wr.week_number desc
      limit 1;
    end if;
  end if;

  if v_current_week_start is null then
    v_current_week_start := v_end_date;
    v_current_week_end := v_end_date;
  end if;

  if v_prev_week_start is null then
    v_prev_week_start := v_current_week_start - 7;
    v_prev_week_end := v_current_week_end - 7;
  end if;

  return (
    with date_context as (
      select
        gs.d::date as tx_date,
        dtd.period_id::uuid as period_id,
        coalesce(dtd.target_daily_all_type, 0)::numeric as target_all,
        coalesce(dtd.target_daily_focus, 0)::numeric as target_focus,
        coalesce(wk.week_number, greatest(least(((extract(day from gs.d)::int - 1) / 7)::int + 1, 4), 1)) as week_number,
        coalesce(
          wk.week_start,
          date_trunc('month', gs.d)::date
            + ((greatest(least(((extract(day from gs.d)::int - 1) / 7)::int + 1, 4), 1) - 1) * interval '7 day')
        )::date as week_start,
        coalesce(
          wk.week_end,
          least(
            (date_trunc('month', gs.d)::date + ((greatest(least(((extract(day from gs.d)::int - 1) / 7)::int + 1, 4), 1) * interval '7 day') - interval '1 day'))::date,
            (date_trunc('month', gs.d)::date + interval '1 month - 1 day')::date
          )
        )::date as week_end
      from generate_series(v_start_date, v_end_date, interval '1 day') gs(d)
      left join lateral public.get_daily_target_dashboard(p_user_id, gs.d::date) dtd on true
      left join public.target_periods tp
        on tp.id = dtd.period_id
      left join lateral (
        with week_rows as (
          select
            gen.week_number,
            coalesce(wt.start_day, ((gen.week_number - 1) * 7) + 1) as start_day,
            coalesce(
              wt.end_day,
              case
                when gen.week_number < 4 then gen.week_number * 7
                else extract(day from tp.end_date)::int
              end
            ) as end_day
          from generate_series(1, 4) as gen(week_number)
          left join public.weekly_targets wt
            on wt.period_id = dtd.period_id
           and wt.week_number = gen.week_number
        )
        select
          wr.week_number,
          greatest(
            tp.start_date,
            (tp.start_date + (wr.start_day - 1) * interval '1 day')::date
          ) as week_start,
          least(
            tp.end_date,
            (tp.start_date + (wr.end_day - 1) * interval '1 day')::date
          ) as week_end
        from week_rows wr
        where tp.id is not null
          and extract(day from gs.d)::int between wr.start_day and wr.end_day
        order by wr.week_number
        limit 1
      ) wk on true
    ),
    period_targets as (
      select
        pd.period_id,
        coalesce(ut.target_fokus_detail, '{}'::jsonb) as effective_legacy_detail,
        coalesce(ut.target_special_detail, '{}'::jsonb) as effective_special_detail
      from (
        select distinct dc.period_id
        from date_context dc
        where dc.period_id is not null
      ) pd
      left join lateral (
        select
          ut.target_fokus_detail,
          ut.target_special_detail
        from public.user_targets ut
        where ut.user_id = p_user_id
          and ut.period_id = pd.period_id
        order by ut.updated_at desc
        limit 1
      ) ut on true
    ),
    focus_products as (
      select distinct
        pt.period_id,
        fp.product_id
      from period_targets pt
      join lateral public.get_target_focus_product_ids(
        pt.period_id,
        pt.effective_legacy_detail,
        pt.effective_special_detail
      ) fp on true
    ),
    special_products as (
      select distinct
        pt.period_id,
        sbp.product_id
      from period_targets pt
      join lateral jsonb_each(pt.effective_special_detail) d on true
      join public.special_focus_bundles sb on sb.id = d.key::uuid
      join public.special_focus_bundle_products sbp on sbp.bundle_id = sb.id
    ),
    sale_bonus as (
      select
        so.id as sales_sell_out_id,
        case
          when coalesce(sum(sbe.bonus_amount), 0) > 0
            then coalesce(sum(sbe.bonus_amount), 0)::numeric
          when coalesce(so.estimated_bonus, 0) > 0
            then coalesce(so.estimated_bonus, 0)::numeric
          else 0::numeric
        end as total_bonus
      from public.sales_sell_out so
      left join public.sales_bonus_events sbe on sbe.sales_sell_out_id = so.id
      group by so.id, so.estimated_bonus
    ),
    range_sales as (
      select
        so.id,
        so.transaction_date::date as tx_date,
        dc.period_id,
        dc.week_number,
        dc.week_start,
        dc.week_end,
        pv.product_id,
        coalesce(so.price_at_transaction, 0)::numeric as omzet,
        coalesce(sb.total_bonus, 0)::numeric as bonus,
        trim(concat_ws(' ',
          nullif(trim(coalesce(p.model_name, '')), ''),
          nullif(trim(coalesce(pv.ram_rom, '')), '')
        )) as type_label
      from public.sales_sell_out so
      join public.product_variants pv on pv.id = so.variant_id
      join public.products p on p.id = pv.product_id
      left join sale_bonus sb on sb.sales_sell_out_id = so.id
      left join date_context dc on dc.tx_date = so.transaction_date::date
      where so.promotor_id = p_user_id
        and so.transaction_date between v_start_date and v_end_date
        and so.deleted_at is null
        and coalesce(so.is_chip_sale, false) = false
    ),
    sales_enriched as (
      select
        rs.*,
        exists (
          select 1
          from focus_products fp
          where fp.period_id = rs.period_id
            and fp.product_id = rs.product_id
        ) as is_focus,
        exists (
          select 1
          from special_products sp
          where sp.period_id = rs.period_id
            and sp.product_id = rs.product_id
        ) as is_special
      from range_sales rs
    ),
    daily_rollup as (
      select
        dc.tx_date,
        dc.week_number,
        dc.week_start,
        dc.week_end,
        dc.target_all,
        dc.target_focus,
        coalesce(count(se.id), 0)::int as all_units,
        coalesce(sum(se.omzet), 0)::numeric as all_actual,
        coalesce(sum(se.bonus), 0)::numeric as bonus,
        coalesce(sum(case when se.is_focus then 1 else 0 end), 0)::int as focus_units,
        coalesce(sum(case when se.is_focus then se.omzet else 0 end), 0)::numeric as focus_actual,
        coalesce(sum(case when se.is_special then 1 else 0 end), 0)::int as special_units,
        coalesce(sum(case when se.is_special then se.omzet else 0 end), 0)::numeric as special_actual
      from date_context dc
      left join sales_enriched se on se.tx_date = dc.tx_date
      group by
        dc.tx_date,
        dc.week_number,
        dc.week_start,
        dc.week_end,
        dc.target_all,
        dc.target_focus
      order by dc.tx_date
    ),
    summary as (
      select
        coalesce(sum(target_all), 0)::numeric as target_total,
        coalesce(sum(all_actual), 0)::numeric as actual_total,
        coalesce(sum(bonus), 0)::numeric as bonus_total,
        coalesce(sum(all_units), 0)::int as units_total,
        coalesce(sum(focus_units), 0)::int as focus_units_total,
        coalesce(sum(special_units), 0)::int as special_units_total
      from daily_rollup
    ),
    weekly_rollup as (
      select
        dr.week_number,
        dr.week_start,
        dr.week_end,
        coalesce(sum(dr.target_all), 0)::numeric as target,
        coalesce(sum(dr.all_actual), 0)::numeric as actual,
        coalesce(sum(dr.all_units), 0)::int as units,
        coalesce(sum(dr.focus_units), 0)::int as focus_units,
        coalesce(sum(dr.special_units), 0)::int as special_units
      from daily_rollup dr
      group by dr.week_number, dr.week_start, dr.week_end
      order by dr.week_start
    ),
    type_rollup as (
      select
        coalesce(nullif(type_label, ''), '-') as type_label,
        count(*)::int as units,
        coalesce(sum(omzet), 0)::numeric as omzet,
        coalesce(sum(bonus), 0)::numeric as bonus
      from sales_enriched
      group by 1
      order by units desc, omzet desc, type_label
    ),
    type_rollup_with_share as (
      select
        tr.*,
        case
          when (select coalesce(sum(units), 0) from type_rollup) > 0
            then (tr.units::numeric * 100.0) / (select sum(units)::numeric from type_rollup)
          else 0
        end as share_pct
      from type_rollup tr
    ),
    current_week_type_sales as (
      select
        trim(concat_ws(' ',
          nullif(trim(coalesce(p.model_name, '')), ''),
          nullif(trim(coalesce(pv.ram_rom, '')), '')
        )) as type_label,
        count(*)::int as units
      from public.sales_sell_out so
      join public.product_variants pv on pv.id = so.variant_id
      join public.products p on p.id = pv.product_id
      where so.promotor_id = p_user_id
        and so.transaction_date between v_current_week_start and least(v_current_week_end, v_end_date)
        and so.deleted_at is null
        and coalesce(so.is_chip_sale, false) = false
      group by 1
    ),
    prev_week_type_sales as (
      select
        trim(concat_ws(' ',
          nullif(trim(coalesce(p.model_name, '')), ''),
          nullif(trim(coalesce(pv.ram_rom, '')), '')
        )) as type_label,
        count(*)::int as units
      from public.sales_sell_out so
      join public.product_variants pv on pv.id = so.variant_id
      join public.products p on p.id = pv.product_id
      where so.promotor_id = p_user_id
        and so.transaction_date between v_prev_week_start and least(v_prev_week_end, v_end_date)
        and so.deleted_at is null
        and coalesce(so.is_chip_sale, false) = false
      group by 1
    ),
    type_trend as (
      select
        coalesce(cur.type_label, prev.type_label) as type_label,
        coalesce(cur.units, 0)::int as current_units,
        coalesce(prev.units, 0)::int as prev_units,
        (coalesce(cur.units, 0) - coalesce(prev.units, 0))::int as delta_units
      from current_week_type_sales cur
      full join prev_week_type_sales prev on prev.type_label = cur.type_label
      where coalesce(cur.units, 0) > 0 or coalesce(prev.units, 0) > 0
    )
    select jsonb_build_object(
      'summary', (
        select jsonb_build_object(
          'start_date', v_start_date,
          'end_date', v_end_date,
          'current_week_start', v_current_week_start,
          'current_week_end', v_current_week_end,
          'prev_week_start', v_prev_week_start,
          'prev_week_end', v_prev_week_end,
          'target_total', s.target_total,
          'actual_total', s.actual_total,
          'bonus_total', s.bonus_total,
          'units_total', s.units_total,
          'focus_units_total', s.focus_units_total,
          'special_units_total', s.special_units_total,
          'gap_total', greatest(s.target_total - s.actual_total, 0),
          'achievement_pct', case when s.target_total > 0 then (s.actual_total * 100.0 / s.target_total) else 0 end
        )
        from summary s
      ),
      'daily_trend', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'date', dr.tx_date,
            'target', dr.target_all,
            'actual', dr.all_actual,
            'units', dr.all_units,
            'target_all', dr.target_all,
            'target_focus', dr.target_focus,
            'all_actual', dr.all_actual,
            'all_units', dr.all_units,
            'focus_actual', dr.focus_actual,
            'focus_units', dr.focus_units,
            'special_actual', dr.special_actual,
            'special_units', dr.special_units,
            'bonus', dr.bonus
          )
          order by dr.tx_date
        )
        from daily_rollup dr
      ), '[]'::jsonb),
      'weekly_details', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'week_number', wr.week_number,
            'week_start', wr.week_start,
            'week_end', wr.week_end,
            'week_label', 'Minggu ' || wr.week_number || ' · ' || to_char(wr.week_start, 'DD Mon'),
            'target', wr.target,
            'actual', wr.actual,
            'units', wr.units,
            'focus_units', wr.focus_units,
            'special_units', wr.special_units,
            'achievement_pct', case when wr.target > 0 then (wr.actual * 100.0 / wr.target) else 0 end
          )
          order by wr.week_start
        )
        from weekly_rollup wr
      ), '[]'::jsonb),
      'type_breakdown', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'type_label', tr.type_label,
            'units', tr.units,
            'omzet', tr.omzet,
            'bonus', tr.bonus,
            'share_pct', tr.share_pct
          )
          order by tr.units desc, tr.omzet desc, tr.type_label
        )
        from type_rollup_with_share tr
      ), '[]'::jsonb),
      'type_trend', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'type_label', tt.type_label,
            'current_units', tt.current_units,
            'prev_units', tt.prev_units,
            'current_week_units', tt.current_units,
            'prev_week_units', tt.prev_units,
            'delta_units', tt.delta_units,
            'delta_pct', case
              when tt.prev_units > 0 then (tt.delta_units::numeric * 100.0 / tt.prev_units)
              when tt.current_units > 0 then 100
              else 0
            end
          )
          order by tt.delta_units desc, tt.current_units desc, tt.type_label
        )
        from type_trend tt
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_promotor_sellout_insight(uuid, date, date) to authenticated;
