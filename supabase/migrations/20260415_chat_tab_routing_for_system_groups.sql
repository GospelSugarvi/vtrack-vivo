alter table public.chat_rooms
  add column if not exists chat_tab text;

alter table public.chat_rooms
  drop constraint if exists chat_rooms_chat_tab_check;

alter table public.chat_rooms
  add constraint chat_rooms_chat_tab_check
  check (chat_tab is null or chat_tab in ('team', 'global', 'announcement', 'store'));

comment on column public.chat_rooms.chat_tab is
'Routing tab in chat list: team/global/announcement/store. Null = auto by room_type.';

update public.chat_rooms
set chat_tab = case
  when room_type in ('toko', 'store') then 'store'
  when room_type = 'announcement' then 'announcement'
  when room_type = 'global' then 'global'
  when room_type in ('tim', 'leader', 'team') then 'team'
  else null
end
where chat_tab is null;

drop function if exists public.get_user_chat_rooms(uuid);
create function public.get_user_chat_rooms(p_user_id uuid)
returns table (
    room_id uuid,
    room_type varchar(20),
    room_name varchar(255),
    room_description text,
    store_id uuid,
    sator_id uuid,
    user1_id uuid,
    user2_id uuid,
    is_muted boolean,
    last_read_at timestamp with time zone,
    unread_count bigint,
    mention_unread_count bigint,
    mention_all_unread_count bigint,
    chat_tab text,
    last_message_content text,
    last_message_time timestamp with time zone,
    last_message_sender_name varchar(255),
    member_count bigint,
    created_at timestamp with time zone
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select
        cr.id as room_id,
        cr.room_type::varchar(20),
        cr.name::varchar(255) as room_name,
        cr.description as room_description,
        cr.store_id,
        cr.sator_id,
        cr.user1_id,
        cr.user2_id,
        cm.is_muted,
        cm.last_read_at,
        coalesce((
            select count(*)
            from public.chat_messages msg
            where msg.room_id = cr.id
              and msg.created_at > coalesce(cm.last_read_at, '1970-01-01'::timestamp with time zone)
              and msg.is_deleted = false
              and msg.sender_id <> p_user_id
        ), 0)::bigint as unread_count,
        coalesce((
            select count(*)
            from public.app_notifications an
            where an.recipient_user_id = p_user_id
              and an.status = 'unread'
              and an.archived_at is null
              and an.category = 'chat'
              and an.type = 'chat_mention'
              and coalesce(an.payload ->> 'room_id', '') = cr.id::text
        ), 0)::bigint as mention_unread_count,
        coalesce((
            select count(*)
            from public.app_notifications an
            where an.recipient_user_id = p_user_id
              and an.status = 'unread'
              and an.archived_at is null
              and an.category = 'chat'
              and an.type = 'chat_mention_all'
              and coalesce(an.payload ->> 'room_id', '') = cr.id::text
        ), 0)::bigint as mention_all_unread_count,
        cr.chat_tab,
        (
            select msg.content
            from public.chat_messages msg
            where msg.room_id = cr.id
              and msg.is_deleted = false
            order by msg.created_at desc
            limit 1
        ) as last_message_content,
        (
            select msg.created_at
            from public.chat_messages msg
            where msg.room_id = cr.id
              and msg.is_deleted = false
            order by msg.created_at desc
            limit 1
        ) as last_message_time,
        (
            select u.full_name::varchar(255)
            from public.chat_messages msg
            join public.users u on u.id = msg.sender_id
            where msg.room_id = cr.id
              and msg.is_deleted = false
            order by msg.created_at desc
            limit 1
        ) as last_message_sender_name,
        (
            select count(*)::bigint
            from public.chat_members mem
            where mem.room_id = cr.id
              and mem.left_at is null
        ) as member_count,
        cr.created_at
    from public.chat_rooms cr
    join public.chat_members cm on cm.room_id = cr.id
    where cm.user_id = p_user_id
      and cm.left_at is null
      and cr.is_active = true
    order by
        case when unread_count > 0 then 0 else 1 end,
        last_message_time desc nulls last,
        cr.created_at desc;
end;
$$;

grant execute on function public.get_user_chat_rooms(uuid) to authenticated;

drop function if exists public.get_system_chat_groups_admin(text, text, uuid, text, boolean);
create function public.get_system_chat_groups_admin(
  p_group_kind text default null,
  p_status text default 'all',
  p_owner_user_id uuid default null,
  p_search text default null,
  p_include_unclassified boolean default true
)
returns table (
  room_id uuid,
  room_type text,
  room_name text,
  room_description text,
  is_active boolean,
  group_mode text,
  system_group_kind text,
  system_owner_user_id uuid,
  owner_name text,
  owner_role text,
  managed_by_admin boolean,
  member_count integer,
  chat_tab text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return query
  with member_counts as (
    select
      cm.room_id,
      count(*)::int as member_count
    from public.chat_members cm
    where cm.left_at is null
    group by cm.room_id
  ),
  base as (
    select
      cr.id as room_id,
      cr.room_type::text as room_type,
      cr.name::text as room_name,
      coalesce(cr.description, '')::text as room_description,
      cr.is_active,
      cr.group_mode,
      cr.system_group_kind,
      coalesce(cr.system_owner_user_id, cr.sator_id) as system_owner_user_id,
      coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, '-'))::text as owner_name,
      lower(coalesce(u.role::text, ''))::text as owner_role,
      cr.managed_by_admin,
      coalesce(mc.member_count, 0) as member_count,
      cr.chat_tab,
      cr.created_at
    from public.chat_rooms cr
    left join public.users u
      on u.id = coalesce(cr.system_owner_user_id, cr.sator_id)
    left join member_counts mc
      on mc.room_id = cr.id
    where (
      cr.group_mode = 'system'
      or (
        p_include_unclassified
        and cr.room_type in ('tim', 'leader')
      )
    )
  )
  select
    b.room_id,
    b.room_type,
    b.room_name,
    b.room_description,
    b.is_active,
    b.group_mode,
    b.system_group_kind,
    b.system_owner_user_id,
    b.owner_name,
    b.owner_role,
    b.managed_by_admin,
    b.member_count,
    b.chat_tab,
    b.created_at
  from base b
  where (
      p_group_kind is null
      or p_group_kind = ''
      or coalesce(b.system_group_kind, '') = p_group_kind
    )
    and (
      p_status = 'all'
      or (p_status = 'active' and b.is_active = true)
      or (p_status = 'inactive' and b.is_active = false)
      or (p_status = 'unclassified' and b.group_mode <> 'system')
    )
    and (
      p_owner_user_id is null
      or b.system_owner_user_id = p_owner_user_id
    )
    and (
      coalesce(trim(p_search), '') = ''
      or b.room_name ilike '%' || trim(p_search) || '%'
      or b.owner_name ilike '%' || trim(p_search) || '%'
      or coalesce(b.room_description, '') ilike '%' || trim(p_search) || '%'
    )
  order by b.created_at desc, b.room_name;
end;
$$;

grant execute on function public.get_system_chat_groups_admin(text, text, uuid, text, boolean) to authenticated;

create or replace function public.set_chat_group_tab_admin(
  p_room_id uuid,
  p_chat_tab text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if p_chat_tab not in ('team', 'global', 'announcement', 'store') then
    raise exception 'Tab chat tidak valid.';
  end if;

  update public.chat_rooms
  set
    chat_tab = p_chat_tab,
    updated_at = now()
  where id = p_room_id;
end;
$$;

grant execute on function public.set_chat_group_tab_admin(uuid, text) to authenticated;
