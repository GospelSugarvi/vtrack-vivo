create or replace function public.normalize_sales_bonus_event_type()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.bonus_type in ('adjustment', 'reversal') then
    return new;
  end if;

  new.bonus_type := public.resolve_sales_bonus_event_type(new.sales_sell_out_id);
  return new;
end;
$$;
