create or replace function public.get_store_stock_detail(p_store_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_access boolean := false;
  v_result json;
begin
  if p_store_id is null then
    return '[]'::json;
  end if;

  select exists(
    select 1
    from public.assignments_promotor_store aps
    where aps.store_id = p_store_id
      and aps.promotor_id = auth.uid()
      and aps.active = true
  ) or exists(
    select 1
    from public.hierarchy_sator_promotor hsp
    join public.assignments_promotor_store aps
      on aps.promotor_id = hsp.promotor_id
     and aps.store_id = p_store_id
     and aps.active = true
    where hsp.sator_id = auth.uid()
      and hsp.active = true
  )
  into v_has_access;

  if not coalesce(v_has_access, false) then
    raise exception 'Unauthorized store access';
  end if;

  with fallback_stock as (
    select
      s.variant_id,
      count(*)::integer as total_stock
    from public.stok s
    where s.store_id = p_store_id
      and coalesce(s.is_sold, false) = false
    group by s.variant_id
  ),
  base as (
    select
      pv.id as variant_id,
      p.model_name,
      p.network_type,
      pv.ram_rom,
      pv.color,
      coalesce(si.quantity, fs.total_stock, 0) as total_stock
    from public.product_variants pv
    join public.products p
      on p.id = pv.product_id
    left join public.store_inventory si
      on si.store_id = p_store_id
     and si.variant_id = pv.id
    left join fallback_stock fs
      on fs.variant_id = pv.id
    where pv.active = true
      and p.status = 'active'
  )
  select coalesce(
    json_agg(
      json_build_object(
        'variant_id', b.variant_id,
        'model_name', b.model_name,
        'network_type', b.network_type,
        'ram_rom', b.ram_rom,
        'color', b.color,
        'total_stock', b.total_stock
      )
      order by b.total_stock desc, b.model_name asc, b.ram_rom asc, b.color asc
    ),
    '[]'::json
  )
  into v_result
  from base b
  where b.total_stock > 0;

  return v_result;
end;
$$;

grant execute on function public.get_store_stock_detail(uuid) to authenticated;
