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
    select
      case
        when coalesce(ut.target_special_detail, '{}'::jsonb) <> '{}'::jsonb
          then coalesce(ut.target_special_detail, '{}'::jsonb)
        else coalesce(ut.target_fokus_detail, '{}'::jsonb)
      end as detail
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

    union

    select
      sb.id as bundle_id,
      coalesce(sb.bundle_name, 'Tipe Khusus')::text as bundle_name
    from target_source ts
    cross join lateral jsonb_object_keys(coalesce(ts.detail, '{}'::jsonb)) as keys(bundle_id_text)
    join public.special_focus_bundles sb
      on sb.id::text = keys.bundle_id_text
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
          ceil(
            greatest(
              bm.target_month - coalesce(abd.actual_before, 0),
              0
            ) / greatest((select remaining_workdays from workday_meta), 1)::numeric
          )
        when lower(coalesce(p_target_mode, 'monthly')) = 'weekly'
          then ceil((bm.target_month * greatest(p_weekly_percentage, 0)) / 100.0)
        else ceil(bm.target_month)
      end::int as target_qty,
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

grant execute on function public.get_promotor_special_rows_snapshot(uuid, uuid, date, date, text, numeric)
to authenticated;
