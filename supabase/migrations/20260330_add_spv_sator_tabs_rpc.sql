create or replace function public.get_spv_sator_tabs()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role
  into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'spv' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'sator_id', hss.sator_id,
        'name', coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'SATOR'))
      )
      order by coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'SATOR'))
    )
    from public.hierarchy_spv_sator hss
    join public.users u on u.id = hss.sator_id
    where hss.spv_id = v_actor_id
      and hss.active = true
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.get_spv_sator_tabs() to authenticated;
