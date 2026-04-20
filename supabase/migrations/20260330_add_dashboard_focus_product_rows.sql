create or replace function public.get_dashboard_focus_product_rows(
  p_scope_role text,
  p_user_id uuid,
  p_start_date date,
  p_end_date date,
  p_period_id uuid default null
)
returns table(
  product_id uuid,
  model_name text,
  series text,
  is_detail_target boolean,
  is_special boolean,
  actual_units integer,
  actual_omzet numeric
)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_scope text := lower(trim(coalesce(p_scope_role, '')));
  v_period_id uuid := p_period_id;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'p_start_date and p_end_date are required';
  end if;

  if p_start_date > p_end_date then
    return;
  end if;

  if v_scope not in ('promotor', 'sator', 'spv') then
    raise exception 'unsupported p_scope_role: %', p_scope_role;
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
    return;
  end if;

  return query
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
  scoped_target_users as (
    select distinct sp.promotor_id as user_id
    from scoped_promotors sp
  ),
  latest_targets as (
    select distinct on (ut.user_id)
      ut.user_id,
      coalesce(ut.target_fokus_detail, '{}'::jsonb) as target_fokus_detail,
      coalesce(ut.target_special_detail, '{}'::jsonb) as target_special_detail
    from public.user_targets ut
    join scoped_target_users stu on stu.user_id = ut.user_id
    where ut.period_id = v_period_id
    order by ut.user_id, ut.updated_at desc nulls last
  ),
  explicit_products as (
    select
      p.id as product_id,
      p.model_name,
      p.series,
      true as is_detail_target,
      false as is_special
    from latest_targets lt
    join jsonb_each(lt.target_fokus_detail) d on true
    join public.fokus_bundles fb on fb.id::text = d.key
    join public.products p on p.model_name = any(fb.product_types)

    union all

    select
      p.id as product_id,
      p.model_name,
      p.series,
      true as is_detail_target,
      true as is_special
    from latest_targets lt
    join jsonb_each(lt.target_special_detail) d on true
    join public.special_focus_bundles sb
      on sb.id::text = d.key
     and sb.period_id = v_period_id
    join public.special_focus_bundle_products sbp on sbp.bundle_id = sb.id
    join public.products p on p.id = sbp.product_id
  ),
  fallback_products as (
    select
      fp.product_id,
      fp.model_name,
      fp.series,
      fp.is_detail_target,
      fp.is_special
    from public.get_fokus_products_by_period(v_period_id) fp
    where not exists (select 1 from explicit_products)
  ),
  target_products as (
    select
      src.product_id,
      src.model_name,
      src.series,
      bool_or(src.is_detail_target) as is_detail_target,
      bool_or(src.is_special) as is_special
    from (
      select * from explicit_products
      union all
      select * from fallback_products
    ) src
    group by src.product_id, src.model_name, src.series
  ),
  sales_rollup as (
    select
      pv.product_id,
      count(*)::int as actual_units,
      coalesce(sum(sso.price_at_transaction), 0)::numeric as actual_omzet
    from public.sales_sell_out sso
    join scoped_promotors sp on sp.promotor_id = sso.promotor_id
    join public.product_variants pv on pv.id = sso.variant_id
    where sso.transaction_date between p_start_date and p_end_date
      and sso.deleted_at is null
      and coalesce(sso.is_chip_sale, false) = false
    group by pv.product_id
  )
  select
    tp.product_id,
    tp.model_name,
    tp.series,
    tp.is_detail_target,
    tp.is_special,
    coalesce(sr.actual_units, 0)::int as actual_units,
    coalesce(sr.actual_omzet, 0)::numeric as actual_omzet
  from target_products tp
  left join sales_rollup sr on sr.product_id = tp.product_id
  order by
    tp.is_special desc,
    tp.is_detail_target desc,
    coalesce(sr.actual_units, 0) desc,
    tp.series,
    tp.model_name;
end;
$function$;

grant execute on function public.get_dashboard_focus_product_rows(text, uuid, date, date, uuid) to authenticated;
