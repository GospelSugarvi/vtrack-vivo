create or replace function public.get_spv_focus_products(
  p_spv_id uuid,
  p_date date default current_date
)
returns table(
  product_id uuid,
  model_name text,
  series text,
  is_detail_target boolean,
  is_special boolean
)
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_period_id uuid;
begin
  perform 1
  from public.users u
  where u.id = p_spv_id
    and u.deleted_at is null;

  if not found then
    return;
  end if;

  select tp.id
  into v_period_id
  from public.target_periods tp
  where p_date between tp.start_date and tp.end_date
  order by tp.start_date desc
  limit 1;

  if v_period_id is null then
    return;
  end if;

  return query
  select *
  from public.get_fokus_products_by_period(v_period_id);
end;
$function$;

grant execute on function public.get_spv_focus_products(uuid, date) to authenticated;
