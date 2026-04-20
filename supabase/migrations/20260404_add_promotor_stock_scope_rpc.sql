create or replace function public.get_promotor_stock_scope(
  p_promotor_id uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_store_name text;
  v_group_id uuid;
  v_group_name text;
  v_group_mode text := '';
  v_scope_store_ids text[];
  v_group_store_count integer := 0;
begin
  if p_promotor_id is null then
    raise exception 'Unauthorized';
  end if;

  select
    aps.store_id,
    st.store_name,
    st.group_id,
    sg.group_name,
    coalesce(sg.stock_handling_mode, '')
  into
    v_store_id,
    v_store_name,
    v_group_id,
    v_group_name,
    v_group_mode
  from public.assignments_promotor_store aps
  join public.stores st on st.id = aps.store_id
  left join public.store_groups sg on sg.id = st.group_id
  where aps.promotor_id = p_promotor_id
    and aps.active = true
    and st.deleted_at is null
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    return jsonb_build_object(
      'store_id', null,
      'store_name', null,
      'group_id', null,
      'group_name', null,
      'group_mode', null,
      'group_store_count', 0,
      'stock_scope_store_ids', jsonb_build_array()
    );
  end if;

  if v_group_id is not null and v_group_mode = 'shared_group' then
    select
      coalesce(array_agg(st.id::text order by st.store_name, st.id), '{}'::text[]),
      count(*)
    into
      v_scope_store_ids,
      v_group_store_count
    from public.stores st
    where st.group_id = v_group_id
      and st.deleted_at is null;
  else
    v_scope_store_ids := array[v_store_id::text];
    if v_group_id is not null then
      select count(*)
      into v_group_store_count
      from public.stores st
      where st.group_id = v_group_id
        and st.deleted_at is null;
    else
      v_group_store_count := 1;
    end if;
  end if;

  return jsonb_build_object(
    'store_id', v_store_id,
    'store_name', v_store_name,
    'group_id', v_group_id,
    'group_name', v_group_name,
    'group_mode', nullif(v_group_mode, ''),
    'group_store_count', coalesce(v_group_store_count, 0),
    'stock_scope_store_ids', to_jsonb(coalesce(v_scope_store_ids, array[v_store_id::text]))
  );
end;
$$;

grant execute on function public.get_promotor_stock_scope(uuid) to authenticated;

comment on function public.get_promotor_stock_scope is
'Returns the effective stock scope for a promotor. Shared groups expand to every active store in the group.';
