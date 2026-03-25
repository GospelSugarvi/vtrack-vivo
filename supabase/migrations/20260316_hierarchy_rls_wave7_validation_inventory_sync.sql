create or replace function public.rebuild_store_inventory_for_store(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_validation_id uuid;
  v_validation_created_at timestamptz;
begin
  if p_store_id is null then
    return;
  end if;

  select sv.id, sv.created_at
  into v_validation_id, v_validation_created_at
  from public.stock_validations sv
  where sv.store_id = p_store_id
    and sv.status = 'completed'
  order by sv.validation_date desc, sv.created_at desc
  limit 1;

  delete from public.store_inventory
  where store_id = p_store_id;

  if v_validation_id is not null then
    insert into public.store_inventory (
      store_id,
      variant_id,
      quantity,
      last_updated
    )
    select
      p_store_id,
      s.variant_id,
      count(*) filter (where svi.is_present = true)::integer as quantity,
      now()
    from public.stock_validation_items svi
    join public.stok s on s.id = svi.stok_id
    where svi.validation_id = v_validation_id
    group by s.variant_id
    having count(*) filter (where svi.is_present = true) > 0;

    insert into public.store_inventory (
      store_id,
      variant_id,
      quantity,
      last_updated
    )
    select
      p_store_id,
      si.variant_id,
      sum(si.qty)::integer as quantity,
      now()
    from public.sales_sell_in si
    where si.store_id = p_store_id
      and si.deleted_at is null
      and si.created_at > v_validation_created_at
    group by si.variant_id
    on conflict (store_id, variant_id)
    do update set
      quantity = public.store_inventory.quantity + excluded.quantity,
      last_updated = now();

    update public.store_inventory inv
    set
      quantity = greatest(inv.quantity - sold.qty_out, 0),
      last_updated = now()
    from (
      select
        so.variant_id,
        count(*)::integer as qty_out
      from public.sales_sell_out so
      where so.store_id = p_store_id
        and so.deleted_at is null
        and so.created_at > v_validation_created_at
      group by so.variant_id
    ) sold
    where inv.store_id = p_store_id
      and inv.variant_id = sold.variant_id;
  else
    insert into public.store_inventory (
      store_id,
      variant_id,
      quantity,
      last_updated
    )
    select
      s.store_id,
      s.variant_id,
      count(*) filter (where coalesce(s.is_sold, false) = false)::integer as quantity,
      now()
    from public.stok s
    where s.store_id = p_store_id
    group by s.store_id, s.variant_id
    having count(*) filter (where coalesce(s.is_sold, false) = false) > 0;
  end if;
end;
$function$;

create or replace function public.sync_validation_items_to_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_validation_id uuid;
  v_store_id uuid;
  v_status text;
begin
  if tg_op = 'DELETE' then
    v_validation_id := old.validation_id;
  else
    v_validation_id := new.validation_id;
  end if;

  select sv.store_id, sv.status
  into v_store_id, v_status
  from public.stock_validations sv
  where sv.id = v_validation_id;

  if v_store_id is not null and v_status = 'completed' then
    perform public.rebuild_store_inventory_for_store(v_store_id);
  end if;

  return coalesce(new, old);
end;
$function$;
