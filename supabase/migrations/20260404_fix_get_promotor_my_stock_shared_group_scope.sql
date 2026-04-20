drop function if exists public.get_promotor_my_stock(uuid);

create or replace function public.get_promotor_my_stock(p_promotor_id uuid)
returns table (
  product_id uuid,
  variant_id uuid,
  model_name text,
  series text,
  ram_rom text,
  color text,
  total_stock bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with active_assignments as (
    select distinct
      aps.store_id,
      st.group_id,
      coalesce(sg.stock_handling_mode, '') as group_mode
    from public.assignments_promotor_store aps
    join public.stores st on st.id = aps.store_id
    left join public.store_groups sg on sg.id = st.group_id
    where aps.promotor_id = p_promotor_id
      and aps.active = true
      and st.deleted_at is null
  ), scoped_stores as (
    select distinct
      coalesce(grouped_st.id, aa.store_id) as store_id
    from active_assignments aa
    left join public.stores grouped_st
      on aa.group_mode = 'shared_group'
      and aa.group_id is not null
      and grouped_st.group_id = aa.group_id
      and grouped_st.deleted_at is null
  ), effective_store_ids as (
    select ss.store_id
    from scoped_stores ss
    where ss.store_id is not null

    union

    select distinct s.store_id
    from public.stok s
    where not exists (
        select 1
        from active_assignments
      )
      and s.promotor_id = p_promotor_id
      and s.store_id is not null
  )
  select
    s.product_id,
    s.variant_id,
    p.model_name::text,
    p.series::text,
    pv.ram_rom::text,
    pv.color::text,
    count(*)::bigint as total_stock
  from public.stok s
  join effective_store_ids es on es.store_id = s.store_id
  join public.products p on p.id = s.product_id
  join public.product_variants pv on pv.id = s.variant_id
  where coalesce(s.is_sold, false) = false
  group by
    s.product_id,
    s.variant_id,
    p.model_name,
    p.series,
    pv.ram_rom,
    pv.color
  order by total_stock desc, p.model_name asc;
end;
$$;

grant execute on function public.get_promotor_my_stock(uuid) to authenticated;

comment on function public.get_promotor_my_stock is
'Get promotor stock using active store assignment scope. Shared groups aggregate all store stock in the same group.';
