create or replace function public.get_spv_stock_management_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_area text := '-';
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'spv' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select coalesce(nullif(trim(u.area), ''), '-')
  into v_area
  from public.users u
  where u.id = v_actor_id;

  return jsonb_build_object(
    'area_name', v_area,
    'stores',
    coalesce((
      with store_scope as (
        select st.id, st.store_name
        from public.stores st
        where st.area = v_area
        order by st.store_name
      ),
      chip_counts as (
        select s.store_id, count(*)::int as chip_count
        from public.stok s
        where s.store_id in (select id from store_scope)
          and s.tipe_stok = 'chip'
          and s.is_sold = false
        group by s.store_id
      ),
      pending_rows as (
        select r.store_id, count(*)::int as pending_chip_count
        from public.stock_chip_requests r
        where r.store_id in (select id from store_scope)
          and r.status = 'pending'
        group by r.store_id
      )
      select jsonb_agg(
        jsonb_build_object(
          'store_id', ss.id,
          'store_name', ss.store_name,
          'chip_count', coalesce(cc.chip_count, 0),
          'pending_chip_count', coalesce(pr.pending_chip_count, 0)
        )
        order by coalesce(cc.chip_count, 0) desc, ss.store_name
      )
      from store_scope ss
      left join chip_counts cc on cc.store_id = ss.id
      left join pending_rows pr on pr.store_id = ss.id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_spv_stock_management_snapshot() to authenticated;
