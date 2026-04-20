create or replace function public.get_team_daily_leaderboard(
  p_sator_id uuid,
  p_date date default current_date
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  return (
    with latest_store_assignment as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        aps.store_id
      from public.assignments_promotor_store aps
      where aps.active = true
      order by aps.promotor_id, aps.created_at desc, aps.store_id
    ),
    roster as (
      select
        u.id as promotor_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'Promotor')) as promotor_name,
        coalesce(st.store_name, '-') as store_name
      from public.hierarchy_sator_promotor hsp
      join public.users u
        on u.id = hsp.promotor_id
      left join latest_store_assignment lsa
        on lsa.promotor_id = u.id
      left join public.stores st
        on st.id = lsa.store_id
      where hsp.sator_id = p_sator_id
        and hsp.active = true
        and u.role = 'promotor'
    ),
    sale_scope as (
      select
        s.promotor_id,
        s.price_at_transaction,
        s.created_at,
        trim(
          concat_ws(
            ' ',
            nullif(trim(coalesce(p.model_name, '')), ''),
            nullif(trim(coalesce(pv.ram_rom, '')), ''),
            nullif(trim(coalesce(pv.color, '')), '')
          )
        ) as variant_name
      from public.sales_sell_out s
      join public.product_variants pv
        on pv.id = s.variant_id
      join public.products p
        on p.id = pv.product_id
      where s.transaction_date = p_date
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false
        and s.promotor_id in (select promotor_id from roster)
    ),
    sales_agg as (
      select
        r.promotor_id,
        r.promotor_name,
        r.store_name,
        count(ss.promotor_id)::int as total_units,
        coalesce(sum(ss.price_at_transaction), 0)::numeric as total_revenue,
        coalesce(dtd.target_daily_all_type, 0)::numeric as daily_target,
        (
          select string_agg(x.variant_name, ', ' order by x.latest_created_at desc)
          from (
            select
              coalesce(nullif(trim(ss2.variant_name), ''), '-') as variant_name,
              max(ss2.created_at) as latest_created_at
            from sale_scope ss2
            where ss2.promotor_id = r.promotor_id
            group by coalesce(nullif(trim(ss2.variant_name), ''), '-')
          ) x
        ) as variants_sold
      from roster r
      left join sale_scope ss
        on ss.promotor_id = r.promotor_id
      left join lateral public.get_daily_target_dashboard(r.promotor_id, p_date) dtd
        on true
      group by
        r.promotor_id,
        r.promotor_name,
        r.store_name,
        dtd.target_daily_all_type
    ),
    ranked as (
      select
        row_number() over (
          order by sa.total_revenue desc, sa.total_units desc, sa.promotor_name
        )::int as rank,
        sa.promotor_id,
        sa.promotor_name,
        sa.store_name,
        sa.daily_target,
        sa.total_revenue,
        sa.total_units,
        coalesce(sa.variants_sold, '-') as variants_sold
      from sales_agg sa
      where sa.total_units > 0
         or sa.total_revenue > 0
    )
    select coalesce(
      json_agg(
        json_build_object(
          'rank', ranked.rank,
          'promotor_id', ranked.promotor_id,
          'promotor_name', ranked.promotor_name,
          'store_name', ranked.store_name,
          'daily_target', ranked.daily_target,
          'total_revenue', ranked.total_revenue,
          'total_units', ranked.total_units,
          'variants_sold', ranked.variants_sold
        )
        order by ranked.rank
      ),
      '[]'::json
    )
    from ranked
  );
end;
$function$;
