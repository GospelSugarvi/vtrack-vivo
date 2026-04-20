create or replace function public.ensure_broadcast_rooms_admin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_global_id uuid;
  v_announcement_id uuid;
  v_total_users integer := 0;
  v_global_members integer := 0;
  v_announcement_members integer := 0;
begin
  if not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select cr.id
  into v_global_id
  from public.chat_rooms cr
  where cr.room_type = 'global'
  order by cr.is_active desc, cr.created_at asc
  limit 1;

  if v_global_id is null then
    insert into public.chat_rooms (
      room_type,
      name,
      description,
      is_active,
      created_by,
      group_mode,
      managed_by_admin,
      chat_tab
    ) values (
      'global',
      'Global',
      'Diskusi umum semua tim',
      true,
      v_actor_id,
      'general',
      true,
      'global'
    )
    returning id into v_global_id;
  else
    update public.chat_rooms
    set
      is_active = true,
      name = coalesce(nullif(trim(name), ''), 'Global'),
      chat_tab = 'global',
      updated_at = now()
    where id = v_global_id;
  end if;

  select cr.id
  into v_announcement_id
  from public.chat_rooms cr
  where cr.room_type = 'announcement'
  order by cr.is_active desc, cr.created_at asc
  limit 1;

  if v_announcement_id is null then
    insert into public.chat_rooms (
      room_type,
      name,
      description,
      is_active,
      created_by,
      group_mode,
      managed_by_admin,
      chat_tab
    ) values (
      'announcement',
      'Info',
      'Pengumuman resmi dari Admin/SPV',
      true,
      v_actor_id,
      'general',
      true,
      'announcement'
    )
    returning id into v_announcement_id;
  else
    update public.chat_rooms
    set
      is_active = true,
      name = coalesce(nullif(trim(name), ''), 'Info'),
      chat_tab = 'announcement',
      updated_at = now()
    where id = v_announcement_id;
  end if;

  select count(*)::int
  into v_total_users
  from public.users u
  where u.deleted_at is null;

  insert into public.chat_members (room_id, user_id, role)
  select v_global_id, u.id, 'member'
  from public.users u
  where u.deleted_at is null
  on conflict (room_id, user_id) do update
  set left_at = null;

  insert into public.chat_members (room_id, user_id, role)
  select v_announcement_id, u.id, 'member'
  from public.users u
  where u.deleted_at is null
  on conflict (room_id, user_id) do update
  set left_at = null;

  select count(*)::int into v_global_members
  from public.chat_members cm
  where cm.room_id = v_global_id
    and cm.left_at is null;

  select count(*)::int into v_announcement_members
  from public.chat_members cm
  where cm.room_id = v_announcement_id
    and cm.left_at is null;

  return jsonb_build_object(
    'global_room_id', v_global_id,
    'announcement_room_id', v_announcement_id,
    'active_users', v_total_users,
    'global_members', v_global_members,
    'announcement_members', v_announcement_members
  );
end;
$$;

grant execute on function public.ensure_broadcast_rooms_admin() to authenticated;
