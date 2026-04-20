create or replace function public.get_daily_ranking(
    p_date date default current_date,
    p_area_id uuid default null,
    p_limit integer default 50
)
returns table(
    rank integer,
    promotor_id uuid,
    promotor_name text,
    store_name text,
    total_sales integer,
    total_bonus numeric,
    daily_target numeric,
    has_sold boolean,
    primary_type text,
    extra_type_count integer,
    type_breakdown jsonb
)
language plpgsql
security definer
set search_path = public
as $function$
begin
  return query
  with sale_bonus as (
    select
      so.id as sales_sell_out_id,
      case
        when coalesce(sum(sbe.bonus_amount), 0) > 0 then coalesce(sum(sbe.bonus_amount), 0)::numeric
        when coalesce(so.estimated_bonus, 0) > 0 then coalesce(so.estimated_bonus, 0)::numeric
        else 0::numeric
      end as total_bonus
    from public.sales_sell_out so
    left join public.sales_bonus_events sbe
      on sbe.sales_sell_out_id = so.id
    group by so.id, so.estimated_bonus
  ),
  sale_rows as (
    select
      so.promotor_id,
      trim(
        concat_ws(
          ' ',
          nullif(trim(coalesce(p.model_name, '')), ''),
          nullif(trim(coalesce(pv.ram_rom, '')), '')
        )
      ) as type_label,
      coalesce(sb.total_bonus, 0)::numeric as bonus_amount,
      coalesce(so.price_at_transaction, 0)::numeric as srp_amount
    from public.sales_sell_out so
    join public.product_variants pv on pv.id = so.variant_id
    join public.products p on p.id = pv.product_id
    left join sale_bonus sb on sb.sales_sell_out_id = so.id
    where so.transaction_date = p_date
      and so.deleted_at is null
      and coalesce(so.is_chip_sale, false) = false
  ),
  promotor_totals as (
    select
      sr.promotor_id,
      count(*)::integer as sales_count,
      coalesce(sum(sr.bonus_amount), 0)::numeric as bonus_total
    from sale_rows sr
    group by sr.promotor_id
  ),
  type_totals as (
    select
      sr.promotor_id,
      case
        when coalesce(nullif(sr.type_label, ''), '') = '' then '-'
        else sr.type_label
      end as type_label,
      count(*)::integer as unit_count,
      coalesce(sum(sr.bonus_amount), 0)::numeric as bonus_total,
      coalesce(sum(sr.srp_amount), 0)::numeric as srp_total
    from sale_rows sr
    group by sr.promotor_id, 2
  ),
  type_ranked as (
    select
      tt.*,
      row_number() over (
        partition by tt.promotor_id
        order by tt.unit_count desc, tt.srp_total desc, tt.type_label
      ) as row_num,
      count(*) over (partition by tt.promotor_id)::integer as type_count
    from type_totals tt
  ),
  type_agg as (
    select
      tr.promotor_id,
      max(case when tr.row_num = 1 then tr.type_label end) as primary_type,
      max(tr.type_count)::integer as type_count,
      jsonb_agg(
        jsonb_build_object(
          'type_label', tr.type_label,
          'unit_count', tr.unit_count,
          'bonus_total', tr.bonus_total,
          'srp_total', tr.srp_total
        )
        order by tr.unit_count desc, tr.srp_total desc, tr.type_label
      ) as type_breakdown
    from type_ranked tr
    group by tr.promotor_id
  ),
  all_promotors as (
    select
      u.id as promotor_id,
      coalesce(nullif(btrim(u.nickname), ''), u.full_name) as promotor_name,
      st.store_name,
      coalesce(pt.sales_count, 0)::integer as total_sales,
      coalesce(pt.bonus_total, 0)::numeric as total_bonus,
      coalesce(dtd.target_daily_all_type, 0)::numeric as daily_target,
      (coalesce(pt.sales_count, 0) > 0) as has_sold,
      coalesce(ta.primary_type, '-') as primary_type,
      greatest(coalesce(ta.type_count, 0) - 1, 0)::integer as extra_type_count,
      coalesce(ta.type_breakdown, '[]'::jsonb) as type_breakdown
    from public.users u
    join public.assignments_promotor_store aps
      on aps.promotor_id = u.id
     and aps.active = true
    join public.stores st
      on st.id = aps.store_id
    left join promotor_totals pt
      on pt.promotor_id = u.id
    left join type_agg ta
      on ta.promotor_id = u.id
    left join lateral public.get_daily_target_dashboard(u.id, p_date) dtd
      on true
    where u.role = 'promotor'
      and u.deleted_at is null
  )
  select
    row_number() over (
      order by ap.total_bonus desc, ap.total_sales desc, ap.promotor_name
    )::integer as rank,
    ap.promotor_id,
    ap.promotor_name,
    ap.store_name,
    ap.total_sales,
    ap.total_bonus,
    ap.daily_target,
    ap.has_sold,
    ap.primary_type,
    ap.extra_type_count,
    ap.type_breakdown
  from all_promotors ap
  order by ap.total_bonus desc, ap.total_sales desc, ap.promotor_name
  limit p_limit;
end;
$function$;
