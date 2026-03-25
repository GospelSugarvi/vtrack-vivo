-- Phase 2: Dual-write to ledger and history tables
-- Date: 2026-03-10
-- Purpose:
-- 1. Keep existing flows working
-- 2. Start writing to new history/ledger tables introduced in Phase 1
-- 3. Avoid breaking current dashboard/reporting compatibility

-- =========================================================
-- 1. SELL OUT ATOMIC PROCESS -> WRITE STATUS HISTORY + BONUS EVENT
-- =========================================================

drop function if exists public.process_sell_out_atomic(
  uuid,uuid,text,numeric,text,text,text,text,text,text,text
);

create or replace function public.process_sell_out_atomic(
  p_promotor_id uuid,
  p_stok_id uuid,
  p_serial_imei text,
  p_price_at_transaction numeric,
  p_payment_method text,
  p_leasing_provider text,
  p_customer_name text,
  p_customer_phone text,
  p_customer_type text,
  p_image_proof_url text,
  p_notes text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock record;
  v_sale_id uuid;
  v_is_chip_sale boolean := false;
  v_period_id uuid;
  v_bonus_amount numeric := 0;
  v_bonus_type text := 'excluded';
begin
  if p_promotor_id is null or p_stok_id is null or coalesce(p_serial_imei, '') = '' then
    raise exception 'p_promotor_id, p_stok_id, and p_serial_imei are required';
  end if;

  if auth.uid() is not null and auth.uid() <> p_promotor_id then
    raise exception 'Unauthorized sell-out context';
  end if;

  if coalesce(p_customer_name, '') = '' then
    raise exception 'Customer name is required';
  end if;

  if coalesce(p_price_at_transaction, 0) <= 0 then
    raise exception 'Price must be greater than 0';
  end if;

  if coalesce(p_payment_method, '') not in ('cash', 'kredit') then
    raise exception 'Payment method must be cash or kredit';
  end if;

  if coalesce(p_customer_type, '') not in ('toko', 'vip_call') then
    raise exception 'Customer type must be toko or vip_call';
  end if;

  if p_payment_method = 'kredit' and coalesce(p_leasing_provider, '') = '' then
    raise exception 'Leasing provider is required for kredit payment';
  end if;

  select s.id, s.imei, s.store_id, s.variant_id, s.is_sold, s.tipe_stok, coalesce(s.bonus_amount, 0) as bonus_amount
  into v_stock
  from public.stok s
  where s.id = p_stok_id
    and s.imei = p_serial_imei
  for update;

  if not found then
    raise exception 'Stock/IMEI not found';
  end if;

  if v_stock.is_sold then
    raise exception 'IMEI already sold';
  end if;

  v_is_chip_sale := coalesce(v_stock.tipe_stok, '') = 'chip';

  insert into public.sales_sell_out (
    promotor_id,
    store_id,
    stok_id,
    variant_id,
    transaction_date,
    serial_imei,
    price_at_transaction,
    payment_method,
    leasing_provider,
    status,
    image_proof_url,
    notes,
    customer_name,
    customer_phone,
    customer_type,
    is_chip_sale,
    chip_label_visible
  ) values (
    p_promotor_id,
    v_stock.store_id,
    v_stock.id,
    v_stock.variant_id,
    current_date,
    v_stock.imei,
    p_price_at_transaction,
    p_payment_method,
    case when p_payment_method = 'kredit' then p_leasing_provider else null end,
    'verified',
    nullif(p_image_proof_url, ''),
    nullif(p_notes, ''),
    p_customer_name,
    nullif(p_customer_phone, ''),
    p_customer_type,
    v_is_chip_sale,
    v_is_chip_sale
  ) returning id into v_sale_id;

  insert into public.sales_sell_out_status_history (
    sales_sell_out_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) values (
    v_sale_id,
    null,
    'verified',
    'Created by process_sell_out_atomic',
    p_promotor_id
  );

  update public.stok
  set
    is_sold = true,
    sold_at = now(),
    sold_price = p_price_at_transaction
  where id = v_stock.id;

  insert into public.stock_movement_log (
    stok_id,
    imei,
    movement_type,
    moved_by,
    moved_at,
    note
  ) values (
    v_stock.id,
    v_stock.imei,
    'sold',
    p_promotor_id,
    now(),
    concat('Sold to ', p_customer_name, ' (', p_customer_type, ')')
  );

  select tp.id
  into v_period_id
  from public.target_periods tp
  where current_date between tp.start_date and tp.end_date
    and coalesce(tp.status, 'active') = 'active'
  order by tp.start_date desc
  limit 1;

  if v_is_chip_sale then
    v_bonus_amount := 0;
    v_bonus_type := 'chip';
  else
    v_bonus_amount := coalesce(v_stock.bonus_amount, 0);
    v_bonus_type := case
      when v_bonus_amount > 0 then 'range'
      else 'excluded'
    end;
  end if;

  insert into public.sales_bonus_events (
    sales_sell_out_id,
    user_id,
    period_id,
    bonus_type,
    rule_snapshot,
    bonus_amount,
    is_projection,
    calculation_version,
    notes,
    created_by
  ) values (
    v_sale_id,
    p_promotor_id,
    v_period_id,
    v_bonus_type,
    jsonb_build_object(
      'source', 'process_sell_out_atomic',
      'stok_id', v_stock.id,
      'tipe_stok', v_stock.tipe_stok,
      'legacy_bonus_amount', coalesce(v_stock.bonus_amount, 0)
    ),
    v_bonus_amount,
    true,
    'phase2_dual_write_v1',
    case
      when v_is_chip_sale then 'Chip sale excluded from new event bonus ledger'
      when v_bonus_amount > 0 then 'Seeded from stok.bonus_amount legacy value'
      else 'Recorded as excluded/zero until dedicated bonus calculator writes explicit rule'
    end,
    p_promotor_id
  );

  return json_build_object(
    'success', true,
    'sale_id', v_sale_id,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'store_id', v_stock.store_id,
    'variant_id', v_stock.variant_id,
    'is_chip_sale', v_is_chip_sale
  );
end;
$$;

grant execute on function public.process_sell_out_atomic(
  uuid,uuid,text,numeric,text,text,text,text,text,text,text
) to authenticated;

-- =========================================================
-- 2. SELL IN FINALIZATION -> WRITE ORDER STATUS HISTORY
-- =========================================================

drop function if exists public.finalize_sell_in_order(uuid,uuid,date,text,text,jsonb);

create or replace function public.finalize_sell_in_order(
  p_sator_id uuid,
  p_store_id uuid,
  p_order_date date,
  p_source text,
  p_notes text,
  p_items jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_total_items integer := 0;
  v_total_qty integer := 0;
  v_total_value numeric := 0;
  v_store_name text;
begin
  if p_sator_id is null or p_store_id is null then
    raise exception 'p_sator_id and p_store_id are required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a JSON array';
  end if;

  if auth.uid() is not null and auth.uid() <> p_sator_id then
    raise exception 'Unauthorized finalization context';
  end if;

  if coalesce(p_source, '') not in ('manual', 'recommendation') then
    raise exception 'p_source must be manual or recommendation';
  end if;

  with parsed as (
    select
      (x->>'variant_id')::uuid as variant_id,
      greatest(coalesce((x->>'qty')::integer, 0), 0) as qty
    from jsonb_array_elements(p_items) x
  ),
  valid as (
    select
      p.variant_id,
      p.qty,
      pv.srp::numeric as price,
      (p.qty * pv.srp::numeric) as subtotal
    from parsed p
    join public.product_variants pv on pv.id = p.variant_id
    join public.products pr on pr.id = pv.product_id
    where p.qty > 0
      and pv.active = true
      and pr.status = 'active'
  )
  select
    count(*)::integer,
    coalesce(sum(qty), 0)::integer,
    coalesce(sum(subtotal), 0)::numeric
  into v_total_items, v_total_qty, v_total_value
  from valid;

  if v_total_items = 0 or v_total_qty = 0 then
    raise exception 'No valid order items to finalize';
  end if;

  insert into public.sell_in_orders (
    sator_id,
    store_id,
    order_date,
    source,
    status,
    notes,
    total_items,
    total_qty,
    total_value,
    finalized_at,
    finalized_by
  ) values (
    p_sator_id,
    p_store_id,
    coalesce(p_order_date, current_date),
    p_source,
    'finalized',
    p_notes,
    v_total_items,
    v_total_qty,
    v_total_value,
    now(),
    p_sator_id
  )
  returning id into v_order_id;

  insert into public.sell_in_order_status_history (
    order_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) values (
    v_order_id,
    null,
    'finalized',
    'Created by finalize_sell_in_order',
    p_sator_id
  );

  with parsed as (
    select
      (x->>'variant_id')::uuid as variant_id,
      greatest(coalesce((x->>'qty')::integer, 0), 0) as qty
    from jsonb_array_elements(p_items) x
  ),
  valid as (
    select
      p.variant_id,
      p.qty,
      pv.srp::numeric as price,
      (p.qty * pv.srp::numeric) as subtotal
    from parsed p
    join public.product_variants pv on pv.id = p.variant_id
    join public.products pr on pr.id = pv.product_id
    where p.qty > 0
      and pv.active = true
      and pr.status = 'active'
  )
  insert into public.sell_in_order_items (order_id, variant_id, qty, price, subtotal)
  select v_order_id, variant_id, qty, price, subtotal
  from valid;

  insert into public.sales_sell_in (
    sator_id,
    store_id,
    variant_id,
    transaction_date,
    qty,
    total_value,
    notes
  )
  select
    p_sator_id,
    p_store_id,
    i.variant_id,
    coalesce(p_order_date, current_date),
    i.qty,
    i.subtotal,
    concat('Finalized order #', v_order_id::text, ' (', p_source, ')')
  from public.sell_in_order_items i
  where i.order_id = v_order_id;

  select st.store_name
  into v_store_name
  from public.stores st
  where st.id = p_store_id;

  return json_build_object(
    'success', true,
    'order_id', v_order_id,
    'store_id', p_store_id,
    'store_name', coalesce(v_store_name, ''),
    'order_date', coalesce(p_order_date, current_date),
    'source', p_source,
    'status', 'finalized',
    'total_items', v_total_items,
    'total_qty', v_total_qty,
    'total_value', v_total_value,
    'finalized_at', now()
  );
end;
$$;

grant execute on function public.finalize_sell_in_order(uuid,uuid,date,text,text,jsonb) to authenticated;

-- =========================================================
-- 3. CHIP REQUEST FLOW -> WRITE REQUEST HISTORY
-- =========================================================

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

  select s.*
  into v_stock
  from public.stok s
  where s.id = p_stok_id
  for update;

  if not found then
    raise exception 'Stock not found';
  end if;

  if v_stock.tipe_stok <> 'fresh' then
    raise exception 'Only fresh stock can request chip status';
  end if;

  select hsp.sator_id
  into v_sator_id
  from public.hierarchy_sator_promotor hsp
  where hsp.promotor_id = v_user_id
    and hsp.active = true
  order by hsp.created_at desc nulls last
  limit 1;

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

  insert into public.stock_chip_request_history (
    stock_chip_request_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) values (
    v_request_id,
    null,
    'pending',
    'Created by submit_chip_request',
    v_user_id
  );

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

create or replace function public.review_chip_request(
  p_request_id uuid,
  p_action text,
  p_rejection_note text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request record;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if coalesce(p_action, '') not in ('approved', 'rejected') then
    raise exception 'Action must be approved or rejected';
  end if;

  select r.*
  into v_request
  from public.stock_chip_requests r
  where r.id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;

  update public.stock_chip_requests
  set
    status = p_action,
    approved_at = now(),
    approved_by = v_user_id,
    rejection_note = case when p_action = 'rejected' then nullif(trim(coalesce(p_rejection_note, '')), '') else null end
  where id = p_request_id;

  insert into public.stock_chip_request_history (
    stock_chip_request_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) values (
    p_request_id,
    v_request.status,
    p_action,
    case when p_action = 'rejected' then nullif(trim(coalesce(p_rejection_note, '')), '') else v_request.reason end,
    v_user_id
  );

  if p_action = 'approved' then
    update public.stok
    set
      tipe_stok = 'chip',
      chip_reason = v_request.reason,
      chip_approved_by = v_user_id,
      chip_approved_at = now(),
      pending_chip_reason = null,
      chip_requested_by = null,
      chip_requested_at = null,
      updated_at = now()
    where id = v_request.stok_id;

    insert into public.stock_movement_log (
      stok_id,
      imei,
      movement_type,
      moved_by,
      moved_at,
      note
    )
    select
      s.id,
      s.imei,
      'chip',
      v_user_id,
      now(),
      v_request.reason
    from public.stok s
    where s.id = v_request.stok_id;
  else
    update public.stok
    set
      pending_chip_reason = null,
      chip_requested_by = null,
      chip_requested_at = null,
      updated_at = now()
    where id = v_request.stok_id;
  end if;

  return json_build_object('success', true);
end;
$$;

grant execute on function public.submit_chip_request(uuid, text) to authenticated;

create or replace function public.submit_sold_stock_chip_request(
  p_imei text,
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
  v_sale_id uuid;
  v_sator_id uuid;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_imei, '')), '') is null then
    raise exception 'IMEI is required';
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
  where s.imei = trim(p_imei)
    and s.store_id = v_store_id
  for update;

  if not found then
    raise exception 'Stock IMEI not found in your store';
  end if;

  if coalesce(v_stock.is_sold, false) = false then
    raise exception 'Only sold stock can use this request';
  end if;

  if coalesce(v_stock.tipe_stok, '') = 'chip' then
    raise exception 'Stock is already chip';
  end if;

  if exists (
    select 1
    from public.stock_chip_requests r
    where r.stok_id = v_stock.id
      and r.status = 'pending'
      and r.request_type = 'sold_to_chip'
  ) then
    raise exception 'Pending sold-to-chip request already exists';
  end if;

  select sso.id
  into v_sale_id
  from public.sales_sell_out sso
  where sso.stok_id = v_stock.id
    and sso.promotor_id = v_user_id
    and sso.store_id = v_store_id
    and sso.deleted_at is null
  order by sso.transaction_date desc, sso.created_at desc
  limit 1;

  if v_sale_id is null then
    raise exception 'Sale history for this IMEI was not found';
  end if;

  select hsp.sator_id
  into v_sator_id
  from public.hierarchy_sator_promotor hsp
  where hsp.promotor_id = v_user_id
    and hsp.active = true
  order by hsp.created_at desc nulls last
  limit 1;

  insert into public.stock_chip_requests (
    stok_id,
    store_id,
    promotor_id,
    sator_id,
    reason,
    request_type,
    source_sale_id
  ) values (
    v_stock.id,
    v_store_id,
    v_user_id,
    v_sator_id,
    trim(p_reason),
    'sold_to_chip',
    v_sale_id
  )
  returning id into v_request_id;

  insert into public.stock_chip_request_history (
    stock_chip_request_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) values (
    v_request_id,
    null,
    'pending',
    'Created by submit_sold_stock_chip_request',
    v_user_id
  );

  update public.stok
  set
    pending_chip_reason = trim(p_reason),
    chip_requested_by = v_user_id,
    chip_requested_at = now(),
    updated_at = now()
  where id = v_stock.id;

  return json_build_object(
    'success', true,
    'request_id', v_request_id,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'request_type', 'sold_to_chip'
  );
end;
$$;

create or replace function public.review_chip_request(
  p_request_id uuid,
  p_action text,
  p_rejection_note text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_request record;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if coalesce(p_action, '') not in ('approved', 'rejected') then
    raise exception 'Action must be approved or rejected';
  end if;

  select r.*
  into v_request
  from public.stock_chip_requests r
  where r.id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;

  update public.stock_chip_requests
  set
    status = p_action,
    approved_at = now(),
    approved_by = v_user_id,
    rejection_note = case when p_action = 'rejected' then nullif(trim(coalesce(p_rejection_note, '')), '') else null end
  where id = p_request_id;

  insert into public.stock_chip_request_history (
    stock_chip_request_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) values (
    p_request_id,
    v_request.status,
    p_action,
    case
      when p_action = 'rejected' then nullif(trim(coalesce(p_rejection_note, '')), '')
      when coalesce(v_request.request_type, 'fresh_to_chip') = 'sold_to_chip' then concat('Sold stock reopened as chip: ', v_request.reason)
      else v_request.reason
    end,
    v_user_id
  );

  if p_action = 'approved' then
    if coalesce(v_request.request_type, 'fresh_to_chip') = 'sold_to_chip' then
      update public.stok
      set
        is_sold = false,
        sold_at = null,
        sold_price = null,
        tipe_stok = 'chip',
        chip_reason = v_request.reason,
        chip_approved_by = v_user_id,
        chip_approved_at = now(),
        pending_chip_reason = null,
        chip_requested_by = null,
        chip_requested_at = null,
        updated_at = now()
      where id = v_request.stok_id;

      insert into public.stock_movement_log (
        stok_id,
        imei,
        movement_type,
        moved_by,
        moved_at,
        note
      )
      select
        s.id,
        s.imei,
        'chip',
        v_user_id,
        now(),
        concat('Reopened sold stock as chip: ', v_request.reason)
      from public.stok s
      where s.id = v_request.stok_id;
    else
      update public.stok
      set
        tipe_stok = 'chip',
        chip_reason = v_request.reason,
        chip_approved_by = v_user_id,
        chip_approved_at = now(),
        pending_chip_reason = null,
        chip_requested_by = null,
        chip_requested_at = null,
        updated_at = now()
      where id = v_request.stok_id;

      insert into public.stock_movement_log (
        stok_id,
        imei,
        movement_type,
        moved_by,
        moved_at,
        note
      )
      select
        s.id,
        s.imei,
        'chip',
        v_user_id,
        now(),
        v_request.reason
      from public.stok s
      where s.id = v_request.stok_id;
    end if;
  else
    update public.stok
    set
      pending_chip_reason = null,
      chip_requested_by = null,
      chip_requested_at = null,
      updated_at = now()
    where id = v_request.stok_id;
  end if;

  return json_build_object('success', true);
end;
$$;

grant execute on function public.submit_sold_stock_chip_request(text, text) to authenticated;
grant execute on function public.review_chip_request(uuid, text, text) to authenticated;
