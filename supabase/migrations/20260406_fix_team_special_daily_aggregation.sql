create or replace function public.get_promotor_special_rows_snapshot(
  p_promotor_id uuid,
  p_period_id uuid,
  p_start_date date,
  p_end_date date,
  p_target_mode text default 'monthly',
  p_weekly_percentage numeric default 0
)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  with period_bounds as (
    select
      tp.start_date as period_start,
      tp.end_date as period_end
    from public.target_periods tp
    where tp.id = p_period_id
    limit 1
  ),
  target_source as (
    select coalesce(ut.target_special_detail, '{}'::jsonb) as detail
    from public.user_targets ut
    where ut.user_id = p_promotor_id
      and ut.period_id = p_period_id
    order by ut.updated_at desc
    limit 1
  ),
  active_bundles as (
    select
      sb.id as bundle_id,
      coalesce(sb.bundle_name, 'Tipe Khusus')::text as bundle_name
    from public.special_focus_bundles sb
    where sb.period_id = p_period_id
  ),
  bundle_meta as (
    select
      ab.bundle_id,
      ab.bundle_name,
      coalesce((ts.detail ->> ab.bundle_id::text)::numeric, 0) as target_month
    from active_bundles ab
    left join target_source ts on true
  ),
  sales_counts as (
    select
      sbp.bundle_id,
      count(*)::int as actual_qty
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    join public.special_focus_bundle_products sbp on sbp.product_id = pv.product_id
    join active_bundles ab on ab.bundle_id = sbp.bundle_id
    where sso.promotor_id = p_promotor_id
      and sso.transaction_date between p_start_date and least(p_end_date, current_date)
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
    group by sbp.bundle_id
  ),
  actual_before_daily as (
    select
      sbp.bundle_id,
      count(*)::numeric as actual_before
    from public.sales_sell_out sso
    join public.product_variants pv on pv.id = sso.variant_id
    join public.special_focus_bundle_products sbp on sbp.product_id = pv.product_id
    join active_bundles ab on ab.bundle_id = sbp.bundle_id
    join period_bounds pb on true
    where sso.promotor_id = p_promotor_id
      and sso.transaction_date between pb.period_start and greatest(p_start_date - 1, pb.period_start)
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
    group by sbp.bundle_id
  ),
  workday_meta as (
    select public.get_effective_workday_count(
      p_promotor_id,
      p_start_date,
      coalesce((select period_end from period_bounds), p_end_date)
    ) as remaining_workdays
  ),
  rows as (
    select
      bm.bundle_id,
      bm.bundle_name,
      bm.target_month,
      case
        when lower(coalesce(p_target_mode, 'monthly')) = 'daily' then
          greatest(
            bm.target_month - coalesce(abd.actual_before, 0),
            0
          ) / greatest((select remaining_workdays from workday_meta), 1)::numeric
        when lower(coalesce(p_target_mode, 'monthly')) = 'weekly'
          then (bm.target_month * greatest(p_weekly_percentage, 0)) / 100.0
        else bm.target_month
      end as target_qty,
      coalesce(sc.actual_qty, 0) as actual_qty
    from bundle_meta bm
    left join sales_counts sc on sc.bundle_id = bm.bundle_id
    left join actual_before_daily abd on abd.bundle_id = bm.bundle_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'bundle_id', bundle_id,
        'bundle_name', bundle_name,
        'target_qty', target_qty,
        'target_month', target_month,
        'actual_qty', actual_qty,
        'pct', case
          when target_qty > 0 then round((actual_qty::numeric / target_qty::numeric) * 100, 2)
          else 0
        end
      )
      order by bundle_name
    ),
    '[]'::jsonb
  )
  from rows;
$function$;

create or replace function public.get_dashboard_special_rows(
  p_scope_role text,
  p_user_id uuid,
  p_start_date date,
  p_end_date date,
  p_range_mode text default 'monthly',
  p_week_percentage numeric default 0,
  p_period_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_scope text := lower(trim(coalesce(p_scope_role, '')));
  v_range_mode text := lower(trim(coalesce(p_range_mode, 'monthly')));
  v_period_id uuid := p_period_id;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'p_start_date and p_end_date are required';
  end if;

  if p_start_date > p_end_date then
    return '[]'::jsonb;
  end if;

  if v_scope not in ('promotor', 'sator', 'spv') then
    raise exception 'unsupported p_scope_role: %', p_scope_role;
  end if;

  if v_range_mode not in ('daily', 'weekly', 'monthly') then
    v_range_mode := 'monthly';
  end if;

  if v_period_id is null then
    select tp.id
    into v_period_id
    from public.target_periods tp
    where p_end_date between tp.start_date and tp.end_date
    order by tp.start_date desc
    limit 1;
  end if;

  if v_period_id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    with scoped_promotors as (
      select p_user_id as promotor_id
      where v_scope = 'promotor'

      union all

      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where v_scope = 'sator'
        and hsp.sator_id = p_user_id
        and hsp.active = true

      union all

      select hsp.promotor_id
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
       and hsp.active = true
      where v_scope = 'spv'
        and hss.spv_id = p_user_id
        and hss.active = true
    ),
    promotor_rows as (
      select
        sp.promotor_id,
        coalesce(
          public.get_promotor_special_rows_snapshot(
            sp.promotor_id,
            v_period_id,
            p_start_date,
            p_end_date,
            v_range_mode,
            coalesce(p_week_percentage, 0)
          ),
          '[]'::jsonb
        ) as rows
      from scoped_promotors sp
    ),
    expanded as (
      select jsonb_array_elements(pr.rows) as row
      from promotor_rows pr
    ),
    aggregated as (
      select
        coalesce(nullif(row->>'bundle_id', ''), nullif(row->>'bundle_name', ''), md5(row::text)) as bundle_id,
        coalesce(nullif(row->>'bundle_name', ''), 'Tipe Khusus') as bundle_name,
        coalesce(sum(coalesce((row->>'target_qty')::numeric, 0)), 0)::numeric as target_qty_raw,
        coalesce(sum(coalesce((row->>'actual_qty')::numeric, 0)), 0)::numeric as actual_qty
      from expanded
      group by 1, 2
    )
    select jsonb_agg(
      jsonb_build_object(
        'bundle_id', a.bundle_id,
        'bundle_name', a.bundle_name,
        'target_qty', case
          when v_range_mode in ('daily', 'weekly') then ceil(a.target_qty_raw)
          else ceil(a.target_qty_raw)
        end,
        'actual_qty', round(a.actual_qty, 1),
        'pct', case
          when a.target_qty_raw > 0 then round((a.actual_qty / a.target_qty_raw) * 100, 1)
          else 0
        end
      )
      order by a.bundle_name
    )
    from aggregated a
  ), '[]'::jsonb);
end;
$function$;

grant execute on function public.get_promotor_special_rows_snapshot(uuid, uuid, date, date, text, numeric)
to authenticated;
grant execute on function public.get_dashboard_special_rows(text, uuid, date, date, text, numeric, uuid)
to authenticated;
