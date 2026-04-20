alter table public.users
add column if not exists whatsapp_phone text;

comment on column public.users.whatsapp_phone is
'Nomor WhatsApp user untuk shortcut komunikasi dari room chat.';

alter table public.store_groups
add column if not exists chat_room_mode text not null default 'split_store';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'store_groups_chat_room_mode_check'
      and conrelid = 'public.store_groups'::regclass
  ) then
    alter table public.store_groups
    add constraint store_groups_chat_room_mode_check
    check (chat_room_mode in ('split_store', 'single_group'));
  end if;
end;
$$;

comment on column public.store_groups.chat_room_mode is
'split_store = room chat per toko, single_group = satu room chat untuk seluruh toko dalam grup.';

alter table public.chat_rooms
add column if not exists group_id uuid references public.store_groups(id) on delete set null;

create index if not exists idx_chat_rooms_group_id
  on public.chat_rooms(group_id)
  where group_id is not null;

create unique index if not exists idx_chat_rooms_unique_group_toko
  on public.chat_rooms(group_id, room_type)
  where room_type = 'toko' and group_id is not null and is_active = true;

drop function if exists public.get_chat_room_members(uuid, uuid);
create or replace function public.get_chat_room_members(
  p_room_id uuid,
  p_user_id uuid
)
returns table (
  id uuid,
  full_name text,
  nickname text,
  role text,
  whatsapp_phone text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.chat_members cm
    where cm.room_id = p_room_id
      and cm.user_id = p_user_id
      and cm.left_at is null
  ) then
    raise exception 'User is not a member of this room';
  end if;

  return query
  select
    u.id,
    u.full_name::text,
    u.nickname::text,
    u.role::text,
    coalesce(u.whatsapp_phone, '')::text
  from public.chat_members cm
  join public.users u on u.id = cm.user_id
  where cm.room_id = p_room_id
    and cm.left_at is null
    and coalesce(u.status, 'active') = 'active'
  order by coalesce(nullif(u.nickname, ''), u.full_name), u.full_name;
end;
$$;

grant execute on function public.get_chat_room_members(uuid, uuid) to authenticated;

create or replace function public.ensure_group_store_chat_room(
  p_group_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_group_name text;
begin
  if p_group_id is null then
    return null;
  end if;

  select group_name
  into v_group_name
  from public.store_groups
  where id = p_group_id
    and deleted_at is null;

  if v_group_name is null then
    return null;
  end if;

  select cr.id
  into v_room_id
  from public.chat_rooms cr
  where cr.group_id = p_group_id
    and cr.room_type = 'toko'
    and cr.is_active = true
  order by cr.created_at desc
  limit 1;

  if v_room_id is null then
    insert into public.chat_rooms (
      room_type,
      name,
      description,
      group_id,
      is_active
    )
    values (
      'toko',
      'Grup Toko: ' || coalesce(v_group_name, 'Unknown'),
      'Room gabungan untuk toko satu grup',
      p_group_id,
      true
    )
    returning id into v_room_id;
  else
    update public.chat_rooms
    set
      name = 'Grup Toko: ' || coalesce(v_group_name, 'Unknown'),
      description = 'Room gabungan untuk toko satu grup',
      updated_at = now()
    where id = v_room_id;
  end if;

  return v_room_id;
end;
$$;

grant execute on function public.ensure_group_store_chat_room(uuid) to authenticated;

create or replace function public.resolve_store_chat_room(
  p_store_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_group_id uuid;
  v_group_name text;
  v_chat_room_mode text;
  v_store_name text;
begin
  if p_store_id is null then
    return null;
  end if;

  select
    st.group_id,
    st.store_name,
    sg.group_name,
    coalesce(sg.chat_room_mode, 'split_store')
  into
    v_group_id,
    v_store_name,
    v_group_name,
    v_chat_room_mode
  from public.stores st
  left join public.store_groups sg on sg.id = st.group_id
  where st.id = p_store_id
    and st.deleted_at is null
  limit 1;

  if v_group_id is not null and v_chat_room_mode = 'single_group' then
    v_room_id := public.ensure_group_store_chat_room(v_group_id);

    update public.chat_rooms
    set
      is_active = false,
      updated_at = now()
    where room_type = 'toko'
      and store_id in (
        select s.id
        from public.stores s
        where s.group_id = v_group_id
          and s.deleted_at is null
      )
      and coalesce(group_id, '00000000-0000-0000-0000-000000000000'::uuid) <> v_group_id;

    return v_room_id;
  end if;

  update public.chat_rooms
  set
    is_active = false,
    updated_at = now()
  where room_type = 'toko'
    and group_id = v_group_id
    and group_id is not null;

  select id
  into v_room_id
  from public.chat_rooms
  where store_id = p_store_id
    and room_type = 'toko'
  order by created_at desc
  limit 1;

  if v_room_id is null then
    insert into public.chat_rooms (room_type, name, store_id, is_active)
    values (
      'toko',
      'Toko: ' || coalesce(v_store_name, 'Unknown'),
      p_store_id,
      true
    )
    returning id into v_room_id;
  else
    update public.chat_rooms
    set
      is_active = true,
      name = 'Toko: ' || coalesce(v_store_name, 'Unknown'),
      group_id = null,
      updated_at = now()
    where id = v_room_id;
  end if;

  return v_room_id;
end;
$$;

grant execute on function public.resolve_store_chat_room(uuid) to authenticated;

create or replace function public.refresh_store_chat_scope(
  p_store_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_group_id uuid;
  v_chat_room_mode text;
begin
  if p_store_id is null then
    return;
  end if;

  select
    st.group_id,
    coalesce(sg.chat_room_mode, 'split_store')
  into
    v_group_id,
    v_chat_room_mode
  from public.stores st
  left join public.store_groups sg on sg.id = st.group_id
  where st.id = p_store_id
    and st.deleted_at is null
  limit 1;

  v_room_id := public.resolve_store_chat_room(p_store_id);
  if v_room_id is null then
    return;
  end if;

  with scoped_store_ids as (
    select st.id as store_id
    from public.stores st
    where (
      v_group_id is not null
      and v_chat_room_mode = 'single_group'
      and st.group_id = v_group_id
    )
    or st.id = p_store_id
  ),
  scoped_users as (
    select distinct aps.promotor_id as user_id
    from public.assignments_promotor_store aps
    join scoped_store_ids ssi on ssi.store_id = aps.store_id
    where aps.active = true

    union

    select distinct hsp.sator_id as user_id
    from public.assignments_promotor_store aps
    join scoped_store_ids ssi on ssi.store_id = aps.store_id
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    where aps.active = true

    union

    select distinct hss.spv_id as user_id
    from public.assignments_promotor_store aps
    join scoped_store_ids ssi on ssi.store_id = aps.store_id
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    join public.hierarchy_spv_sator hss
      on hss.sator_id = hsp.sator_id
     and hss.active = true
    where aps.active = true
  )
  insert into public.chat_members (room_id, user_id)
  select v_room_id, su.user_id
  from scoped_users su
  on conflict (room_id, user_id) do update
  set left_at = null;

  with scoped_store_ids as (
    select st.id as store_id
    from public.stores st
    where (
      v_group_id is not null
      and v_chat_room_mode = 'single_group'
      and st.group_id = v_group_id
    )
    or st.id = p_store_id
  ),
  scoped_users as (
    select distinct aps.promotor_id as user_id
    from public.assignments_promotor_store aps
    join scoped_store_ids ssi on ssi.store_id = aps.store_id
    where aps.active = true

    union

    select distinct hsp.sator_id as user_id
    from public.assignments_promotor_store aps
    join scoped_store_ids ssi on ssi.store_id = aps.store_id
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    where aps.active = true

    union

    select distinct hss.spv_id as user_id
    from public.assignments_promotor_store aps
    join scoped_store_ids ssi on ssi.store_id = aps.store_id
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    join public.hierarchy_spv_sator hss
      on hss.sator_id = hsp.sator_id
     and hss.active = true
    where aps.active = true
  )
  update public.chat_members cm
  set left_at = now()
  where cm.room_id = v_room_id
    and cm.left_at is null
    and not exists (
      select 1
      from scoped_users su
      where su.user_id = cm.user_id
    );
end;
$$;

create or replace function public.get_store_chat_room_resolved(
  p_store_id uuid
)
returns table (
  id uuid,
  room_type varchar,
  name varchar,
  description text,
  store_id uuid,
  sator_id uuid,
  user1_id uuid,
  user2_id uuid,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
begin
  v_room_id := public.resolve_store_chat_room(p_store_id);
  if v_room_id is null then
    return;
  end if;

  return query
  select
    cr.id,
    cr.room_type::varchar,
    cr.name::varchar,
    cr.description,
    cr.store_id,
    cr.sator_id,
    cr.user1_id,
    cr.user2_id,
    cr.created_at
  from public.chat_rooms cr
  where cr.id = v_room_id
    and cr.is_active = true
  limit 1;
end;
$$;

grant execute on function public.get_store_chat_room_resolved(uuid) to authenticated;

create or replace function public.on_store_group_chat_mode_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  for v_store_id in
    select st.id
    from public.stores st
    where st.group_id = new.id
      and st.deleted_at is null
  loop
    perform public.refresh_store_chat_scope(v_store_id);
  end loop;
  return new;
end;
$$;

drop trigger if exists trigger_store_group_chat_mode_sync on public.store_groups;
create trigger trigger_store_group_chat_mode_sync
after insert or update of chat_room_mode on public.store_groups
for each row execute function public.on_store_group_chat_mode_sync();

create or replace function public.on_store_group_assignment_chat_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_store_chat_scope(new.id);
  return new;
end;
$$;

drop trigger if exists trigger_store_group_assignment_chat_sync on public.stores;
create trigger trigger_store_group_assignment_chat_sync
after insert or update of group_id on public.stores
for each row execute function public.on_store_group_assignment_chat_sync();
