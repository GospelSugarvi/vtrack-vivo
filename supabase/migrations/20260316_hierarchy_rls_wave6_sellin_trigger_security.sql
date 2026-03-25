create or replace function public.process_sell_in_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  insert into public.store_inventory (store_id, variant_id, quantity)
  values (new.store_id, new.variant_id, new.qty)
  on conflict (store_id, variant_id) do update
    set quantity = public.store_inventory.quantity + excluded.quantity,
        last_updated = now();

  return new;
end;
$function$;
