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
  with target_source as (
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
  rows as (
    select
      bm.bundle_id,
      bm.bundle_name,
      bm.target_month,
      case
        when lower(coalesce(p_target_mode, 'monthly')) = 'daily' then ceil(bm.target_month / 24.0)
        when lower(coalesce(p_target_mode, 'monthly')) = 'weekly'
          then ceil((bm.target_month * greatest(p_weekly_percentage, 0)) / 100.0)
        else ceil(bm.target_month)
      end::int as target_qty,
      coalesce(sc.actual_qty, 0) as actual_qty
    from bundle_meta bm
    left join sales_counts sc on sc.bundle_id = bm.bundle_id
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
