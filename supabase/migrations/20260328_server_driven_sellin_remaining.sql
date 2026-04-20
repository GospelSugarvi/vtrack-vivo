create or replace function public.get_sell_in_order_composer_snapshot(
  p_mode text default 'recommendation',
  p_store_id uuid default null,
  p_group_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_mode text := lower(trim(coalesce(p_mode, 'recommendation')));
  v_stores jsonb := '[]'::jsonb;
  v_rows_source jsonb := '[]'::jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_group_name text := '';
  v_selected_store_id uuid;
  v_selected_store_name text := 'Pilih toko';
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if v_mode not in ('recommendation', 'manual') then
    raise exception 'Mode tidak valid.';
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    raise exception 'Profil user tidak ditemukan.';
  end if;

  if coalesce(v_actor.role, '') <> 'sator' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  v_stores := coalesce(public.get_store_stock_status(v_actor_id)::jsonb, '[]'::jsonb);

  if p_group_id is not null then
    select coalesce(sg.group_name, 'Grup Toko')
    into v_group_name
    from public.store_groups sg
    where sg.id = p_group_id;

    v_rows_source := coalesce(
      public.get_group_store_recommendations(p_group_id)::jsonb,
      '[]'::jsonb
    );
    v_selected_store_name := coalesce(nullif(v_group_name, ''), 'Grup Toko');
  else
    if p_store_id is not null then
      v_selected_store_id := p_store_id;
    else
      select nullif(x ->> 'store_id', '')::uuid
      into v_selected_store_id
      from jsonb_array_elements(v_stores) x
      limit 1;
    end if;

    if v_selected_store_id is not null then
      select coalesce(
        (
          select nullif(x ->> 'store_name', '')
          from jsonb_array_elements(v_stores) x
          where nullif(x ->> 'store_id', '')::uuid = v_selected_store_id
          limit 1
        ),
        (
          select st.store_name
          from public.stores st
          where st.id = v_selected_store_id
            and st.deleted_at is null
          limit 1
        ),
        'Toko'
      )
      into v_selected_store_name;

      if not exists (
        select 1
        from jsonb_array_elements(v_stores) x
        where nullif(x ->> 'store_id', '')::uuid = v_selected_store_id
      ) then
        v_stores := jsonb_build_array(
          jsonb_build_object(
            'store_id', v_selected_store_id,
            'store_name', v_selected_store_name,
            'group_name', '',
            'empty_count', 0,
            'low_count', 0
          )
        ) || v_stores;
      end if;

      v_rows_source := coalesce(
        public.get_store_recommendations(v_selected_store_id)::jsonb,
        '[]'::jsonb
      );
    end if;
  end if;

  v_rows := coalesce((
    with raw_rows as (
      select
        x.group_id,
        x.group_name,
        x.representative_store_id,
        x.variant_id,
        x.product_id,
        x.product_name,
        x.variant,
        x.color,
        x.price,
        x.modal,
        x.network_type,
        x.series,
        x.current_stock,
        x.min_stock,
        x.shortage_qty,
        x.warehouse_stock,
        x.available_gudang,
        x.order_qty,
        x.unfulfilled_qty,
        x.can_fulfill,
        x.total_stores,
        x.store_breakdown,
        x.status,
        x.recommendation_status
      from jsonb_to_recordset(v_rows_source) as x(
        group_id uuid,
        group_name text,
        representative_store_id uuid,
        variant_id uuid,
        product_id uuid,
        product_name text,
        variant text,
        color text,
        price numeric,
        modal numeric,
        network_type text,
        series text,
        current_stock integer,
        min_stock integer,
        shortage_qty integer,
        warehouse_stock integer,
        available_gudang integer,
        order_qty integer,
        unfulfilled_qty integer,
        can_fulfill boolean,
        total_stores integer,
        store_breakdown jsonb,
        status text,
        recommendation_status text
      )
    ),
    normalized as (
      select
        rr.group_id,
        rr.group_name,
        rr.representative_store_id,
        rr.variant_id,
        rr.product_id,
        coalesce(rr.product_name, 'Produk') as product_name,
        coalesce(rr.network_type, '') as network_type,
        coalesce(rr.series, '') as series,
        coalesce(rr.variant, '-') as variant,
        coalesce(rr.color, '-') as color,
        coalesce(rr.price, 0) as price,
        coalesce(rr.modal, 0) as modal,
        coalesce(rr.current_stock, 0) as current_stock,
        coalesce(rr.min_stock, 0) as min_stock,
        coalesce(rr.shortage_qty, 0) as shortage_qty,
        coalesce(rr.warehouse_stock, 0) as warehouse_stock,
        coalesce(rr.available_gudang, coalesce(rr.warehouse_stock, 0)) as available_gudang,
        coalesce(rr.order_qty, 0) as order_qty,
        coalesce(rr.unfulfilled_qty, 0) as unfulfilled_qty,
        coalesce(rr.can_fulfill, false) as can_fulfill,
        coalesce(rr.total_stores, 0) as total_stores,
        coalesce(rr.store_breakdown, '[]'::jsonb) as store_breakdown,
        coalesce(rr.status, 'CUKUP') as status,
        coalesce(rr.recommendation_status, '') as recommendation_status,
        case
          when v_mode = 'recommendation' then coalesce(rr.order_qty, 0)
          else 0
        end as selected_qty
      from raw_rows rr
      where v_mode <> 'recommendation'
         or coalesce(rr.order_qty, 0) > 0
    )
    select jsonb_agg(
      jsonb_build_object(
        'group_id', n.group_id,
        'group_name', n.group_name,
        'representative_store_id', n.representative_store_id,
        'variant_id', n.variant_id,
        'product_id', n.product_id,
        'product_name', n.product_name,
        'network_type', n.network_type,
        'series', n.series,
        'variant', n.variant,
        'color', n.color,
        'price', n.price,
        'modal', n.modal,
        'current_stock', n.current_stock,
        'min_stock', n.min_stock,
        'shortage_qty', n.shortage_qty,
        'warehouse_stock', n.warehouse_stock,
        'available_gudang', n.available_gudang,
        'order_qty', n.order_qty,
        'unfulfilled_qty', n.unfulfilled_qty,
        'can_fulfill', n.can_fulfill,
        'total_stores', n.total_stores,
        'store_breakdown', n.store_breakdown,
        'status', n.status,
        'recommendation_status', n.recommendation_status,
        'selected_qty', n.selected_qty
      )
      order by
        n.order_qty desc,
        n.product_name,
        n.network_type,
        n.variant,
        n.color
    )
    from normalized n
  ), '[]'::jsonb);

  return jsonb_build_object(
    'current_user_name', coalesce(nullif(trim(v_actor.full_name), ''), 'SATOR'),
    'stores', coalesce(v_stores, '[]'::jsonb),
    'selected_store_id', v_selected_store_id,
    'selected_store_name', v_selected_store_name,
    'rows', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_sell_in_order_composer_snapshot(text, uuid, uuid) to authenticated;

create or replace function public.get_sell_in_finalization_page_snapshot(
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_summary jsonb := '{}'::jsonb;
  v_pending jsonb := '[]'::jsonb;
  v_finalized jsonb := '[]'::jsonb;
  v_cancelled jsonb := '[]'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  v_summary := coalesce(
    public.get_sell_in_finalization_summary(v_actor_id, p_start_date, p_end_date)::jsonb,
    '{}'::jsonb
  );

  v_pending := coalesce((
    with pending_rows as (
      select *
      from jsonb_to_recordset(coalesce(public.get_pending_orders(v_actor_id)::jsonb, '[]'::jsonb)) as x(
        id uuid,
        store_id uuid,
        store_name text,
        group_name text,
        order_date date,
        source text,
        total_items integer,
        total_qty integer,
        total_value numeric,
        status text,
        created_at timestamptz
      )
      where order_date >= p_start_date
        and order_date <= p_end_date
    )
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'store_id', p.store_id,
        'store_name', coalesce(p.store_name, 'Toko'),
        'group_name', coalesce(p.group_name, ''),
        'order_date', p.order_date,
        'source', p.source,
        'total_items', p.total_items,
        'total_qty', p.total_qty,
        'total_value', p.total_value,
        'status', p.status,
        'created_at', p.created_at
      )
      order by p.created_at desc nulls last, p.id desc
    )
    from pending_rows p
  ), '[]'::jsonb);

  v_finalized := coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'order_date', o.order_date,
        'source', o.source,
        'status', o.status,
        'total_items', o.total_items,
        'total_qty', o.total_qty,
        'total_value', o.total_value,
        'finalized_at', o.finalized_at,
        'notes', o.notes,
        'store_name', coalesce(st.store_name, 'Toko'),
        'group_name', coalesce(sg.group_name, '')
      )
      order by o.finalized_at desc nulls last
    )
    from public.sell_in_orders o
    left join public.stores st on st.id = o.store_id
    left join public.store_groups sg on sg.id = o.group_id
    where o.sator_id = v_actor_id
      and o.status = 'finalized'
      and o.order_date >= p_start_date
      and o.order_date <= p_end_date
  ), '[]'::jsonb);

  v_cancelled := coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'order_date', o.order_date,
        'source', o.source,
        'status', o.status,
        'total_items', o.total_items,
        'total_qty', o.total_qty,
        'total_value', o.total_value,
        'cancelled_at', o.cancelled_at,
        'cancellation_reason', o.cancellation_reason,
        'notes', o.notes,
        'store_name', coalesce(st.store_name, 'Toko'),
        'group_name', coalesce(sg.group_name, '')
      )
      order by o.cancelled_at desc nulls last
    )
    from public.sell_in_orders o
    left join public.stores st on st.id = o.store_id
    left join public.store_groups sg on sg.id = o.group_id
    where o.sator_id = v_actor_id
      and o.status = 'cancelled'
      and o.order_date >= p_start_date
      and o.order_date <= p_end_date
  ), '[]'::jsonb);

  return jsonb_build_object(
    'summary', coalesce(v_summary, '{}'::jsonb),
    'pending_orders', coalesce(v_pending, '[]'::jsonb),
    'finalized_orders', coalesce(v_finalized, '[]'::jsonb),
    'cancelled_orders', coalesce(v_cancelled, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_sell_in_finalization_page_snapshot(date, date) to authenticated;
