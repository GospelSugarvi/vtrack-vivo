create or replace function public.submit_chip_request(
  p_stok_id uuid,
  p_reason text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_store_id uuid;
  v_stock record;
  v_sator_id uuid;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Reason is required';
  end if;

  select aps.store_id
  into v_store_id
  from public.assignments_promotor_store aps
  where aps.promotor_id = v_user_id
    and aps.active = true
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    raise exception 'Promotor store assignment not found';
  end if;

  select s.*
  into v_stock
  from public.stok s
  where s.id = p_stok_id
  for update;

  if not found then
    raise exception 'Stock not found';
  end if;

  if v_stock.promotor_id <> v_user_id then
    raise exception 'Stock does not belong to current promotor';
  end if;

  if v_stock.store_id <> v_store_id then
    raise exception 'Stock is not in your active store';
  end if;

  if coalesce(v_stock.is_sold, false) then
    raise exception 'Sold stock cannot request fresh chip flow';
  end if;

  if v_stock.tipe_stok <> 'fresh' then
    raise exception 'Only fresh stock can request chip status';
  end if;

  if exists (
    select 1
    from public.stock_chip_requests r
    where r.stok_id = v_stock.id
      and r.status = 'pending'
  ) then
    raise exception 'Pending chip request already exists for this stock';
  end if;

  select hsp.sator_id
  into v_sator_id
  from public.hierarchy_sator_promotor hsp
  where hsp.promotor_id = v_user_id
    and hsp.active = true
  order by hsp.created_at desc nulls last
  limit 1;

  if v_sator_id is null then
    raise exception 'Sator assignment not found for current promotor';
  end if;

  insert into public.stock_chip_requests (
    stok_id,
    store_id,
    promotor_id,
    sator_id,
    reason
  ) values (
    v_stock.id,
    v_stock.store_id,
    v_user_id,
    v_sator_id,
    trim(p_reason)
  )
  returning id into v_request_id;

  update public.stok
  set
    pending_chip_reason = trim(p_reason),
    chip_requested_by = v_user_id,
    chip_requested_at = now(),
    updated_at = now()
  where id = v_stock.id;

  return json_build_object(
    'success', true,
    'request_id', v_request_id
  );
end;
$$;

grant execute on function public.submit_chip_request(uuid, text) to authenticated;
