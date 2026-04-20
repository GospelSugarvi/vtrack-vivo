alter table public.chat_rooms
  add column if not exists group_mode text not null default 'general',
  add column if not exists system_group_kind text,
  add column if not exists system_owner_user_id uuid references public.users(id) on delete set null,
  add column if not exists managed_by_admin boolean not null default false;

alter table public.chat_rooms
  drop constraint if exists chat_rooms_room_type_check;

alter table public.chat_rooms
  add constraint chat_rooms_room_type_check
  check (room_type in ('toko', 'tim', 'leader', 'global', 'private', 'announcement'));

alter table public.chat_rooms
  drop constraint if exists chat_rooms_group_mode_check;

alter table public.chat_rooms
  add constraint chat_rooms_group_mode_check
  check (group_mode in ('general', 'system'));

alter table public.chat_rooms
  drop constraint if exists chat_rooms_system_group_kind_check;

alter table public.chat_rooms
  add constraint chat_rooms_system_group_kind_check
  check (
    system_group_kind is null
    or system_group_kind in ('sator_main', 'spv_leader')
  );

alter table public.chat_rooms
  drop constraint if exists valid_leader_chat;

alter table public.chat_rooms
  add constraint valid_leader_chat
  check (
    (room_type = 'leader' and system_owner_user_id is not null)
    or room_type != 'leader'
  );

create index if not exists idx_chat_rooms_group_mode
  on public.chat_rooms(group_mode);

create index if not exists idx_chat_rooms_system_group_kind
  on public.chat_rooms(system_group_kind)
  where system_group_kind is not null;

create index if not exists idx_chat_rooms_system_owner
  on public.chat_rooms(system_owner_user_id)
  where system_owner_user_id is not null;

create table if not exists public.chat_report_requests (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  message_id uuid references public.chat_messages(id) on delete cascade,
  request_type text not null check (request_type in ('spv_to_sator', 'sator_to_store')),
  title text not null,
  note text not null default '',
  field_schema jsonb not null default '[]'::jsonb,
  created_by uuid not null references public.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_chat_report_requests_room
  on public.chat_report_requests(room_id, created_at desc);

create index if not exists idx_chat_report_requests_message
  on public.chat_report_requests(message_id)
  where message_id is not null;

create table if not exists public.chat_report_submissions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.chat_report_requests(id) on delete cascade,
  submission_key text not null,
  responder_user_id uuid references public.users(id) on delete set null,
  responses jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (request_id, submission_key)
);

create index if not exists idx_chat_report_submissions_request
  on public.chat_report_submissions(request_id, updated_at desc);

create or replace function public._touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trigger_chat_report_requests_updated_at on public.chat_report_requests;
create trigger trigger_chat_report_requests_updated_at
before update on public.chat_report_requests
for each row execute function public._touch_updated_at();

drop trigger if exists trigger_chat_report_submissions_updated_at on public.chat_report_submissions;
create trigger trigger_chat_report_submissions_updated_at
before update on public.chat_report_submissions
for each row execute function public._touch_updated_at();

create or replace function public.get_system_chat_group_preview_members(
  p_group_kind text,
  p_owner_user_id uuid
)
returns table (
  user_id uuid,
  full_name text,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(trim(p_group_kind), '') = '' or p_owner_user_id is null then
    return;
  end if;

  if p_group_kind = 'sator_main' then
    return query
    with scope_members as (
      select
        u.id as user_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'User')) as full_name,
        lower(coalesce(u.role::text, 'promotor')) as role,
        0 as role_order,
        0 as owner_order
      from public.users u
      where u.id = p_owner_user_id
        and u.deleted_at is null

      union all

      select
        u.id as user_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'User')) as full_name,
        lower(coalesce(u.role::text, 'spv')) as role,
        1 as role_order,
        1 as owner_order
      from public.hierarchy_spv_sator hss
      join public.users u
        on u.id = hss.spv_id
      where hss.sator_id = p_owner_user_id
        and hss.active = true
        and u.deleted_at is null

      union all

      select
        u.id as user_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'User')) as full_name,
        lower(coalesce(u.role::text, 'promotor')) as role,
        2 as role_order,
        1 as owner_order
      from public.hierarchy_sator_promotor hsp
      join public.users u
        on u.id = hsp.promotor_id
      where hsp.sator_id = p_owner_user_id
        and hsp.active = true
        and u.deleted_at is null
    )
    select
      sm.user_id,
      min(sm.full_name) as full_name,
      min(sm.role) as role
    from scope_members sm
    group by sm.user_id
    order by
      min(sm.owner_order),
      min(sm.role_order),
      min(sm.full_name);
  elsif p_group_kind = 'spv_leader' then
    return query
    with scope_members as (
      select
        u.id as user_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'User')) as full_name,
        lower(coalesce(u.role::text, 'spv')) as role,
        0 as role_order,
        0 as owner_order
      from public.users u
      where u.id = p_owner_user_id
        and u.deleted_at is null

      union all

      select
        u.id as user_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'User')) as full_name,
        lower(coalesce(u.role::text, 'sator')) as role,
        1 as role_order,
        1 as owner_order
      from public.hierarchy_spv_sator hss
      join public.users u
        on u.id = hss.sator_id
      where hss.spv_id = p_owner_user_id
        and hss.active = true
        and u.deleted_at is null
    )
    select
      sm.user_id,
      min(sm.full_name) as full_name,
      min(sm.role) as role
    from scope_members sm
    group by sm.user_id
    order by
      min(sm.owner_order),
      min(sm.role_order),
      min(sm.full_name);
  end if;
end;
$$;

grant execute on function public.get_system_chat_group_preview_members(text, uuid) to authenticated;

create or replace function public.sync_system_chat_group_members(
  p_room_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_kind text;
  v_owner_user_id uuid;
  v_member_count integer := 0;
begin
  select
    cr.system_group_kind,
    cr.system_owner_user_id
  into
    v_group_kind,
    v_owner_user_id
  from public.chat_rooms cr
  where cr.id = p_room_id
    and cr.group_mode = 'system';

  if v_group_kind is null or v_owner_user_id is null then
    raise exception 'Group sistem tidak valid.';
  end if;

  with scoped_members as (
    select gm.user_id
    from public.get_system_chat_group_preview_members(v_group_kind, v_owner_user_id) gm
  )
  select count(*)::int
  into v_member_count
  from scoped_members;

  if v_member_count <= 1 then
    raise exception 'Grup tidak bisa dibuat karena anggota hierarchy belum tersedia.';
  end if;

  insert into public.chat_members (room_id, user_id)
  select p_room_id, sm.user_id
  from public.get_system_chat_group_preview_members(v_group_kind, v_owner_user_id) sm
  on conflict (room_id, user_id) do update
  set left_at = null;

  update public.chat_members cm
  set left_at = now()
  where cm.room_id = p_room_id
    and cm.left_at is null
    and not exists (
      select 1
      from public.get_system_chat_group_preview_members(v_group_kind, v_owner_user_id) sm
      where sm.user_id = cm.user_id
    );

  update public.chat_rooms
  set updated_at = now()
  where id = p_room_id;

  return v_member_count;
end;
$$;

grant execute on function public.sync_system_chat_group_members(uuid) to authenticated;

create or replace function public.get_system_chat_groups_admin(
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

create or replace function public.create_system_chat_group(
  p_room_type text,
  p_group_kind text,
  p_owner_user_id uuid,
  p_name text,
  p_description text default '',
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
  v_owner_role text := '';
begin
  if not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if coalesce(trim(p_name), '') = '' then
    raise exception 'Nama grup wajib diisi.';
  end if;

  if p_room_type not in ('tim', 'leader') then
    raise exception 'Tipe room tidak valid.';
  end if;

  if p_group_kind not in ('sator_main', 'spv_leader') then
    raise exception 'Jenis grup sistem tidak valid.';
  end if;

  if p_room_type = 'tim' and p_group_kind <> 'sator_main' then
    raise exception 'Room tim hanya untuk Grup Utama SATOR.';
  end if;

  if p_room_type = 'leader' and p_group_kind <> 'spv_leader' then
    raise exception 'Room leader hanya untuk Grup Leader SPV.';
  end if;

  select lower(coalesce(role::text, ''))
  into v_owner_role
  from public.users
  where id = p_owner_user_id
    and deleted_at is null;

  if v_owner_role = '' then
    raise exception 'Owner grup tidak ditemukan.';
  end if;

  if p_group_kind = 'sator_main' and v_owner_role <> 'sator' then
    raise exception 'Owner Grup Utama harus user role SATOR.';
  end if;

  if p_group_kind = 'spv_leader' and v_owner_role <> 'spv' then
    raise exception 'Owner Grup Leader harus user role SPV.';
  end if;

  insert into public.chat_rooms (
    room_type,
    name,
    description,
    sator_id,
    is_active,
    group_mode,
    system_group_kind,
    system_owner_user_id,
    managed_by_admin
  )
  values (
    p_room_type,
    trim(p_name),
    coalesce(p_description, ''),
    case when p_group_kind = 'sator_main' then p_owner_user_id else null end,
    p_is_active,
    'system',
    p_group_kind,
    p_owner_user_id,
    true
  )
  returning id into v_room_id;

  perform public.sync_system_chat_group_members(v_room_id);

  return v_room_id;
end;
$$;

grant execute on function public.create_system_chat_group(text, text, uuid, text, text, boolean) to authenticated;

create or replace function public.reclassify_system_chat_group(
  p_room_id uuid,
  p_room_type text,
  p_group_kind text,
  p_owner_user_id uuid,
  p_name text default null,
  p_description text default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if p_group_kind = 'sator_main' and p_room_type <> 'tim' then
    raise exception 'Grup Utama SATOR harus memakai room tim.';
  end if;

  if p_group_kind = 'spv_leader' and p_room_type <> 'leader' then
    raise exception 'Grup Leader SPV harus memakai room leader.';
  end if;

  if p_room_type not in ('tim', 'leader') then
    raise exception 'Tipe room tidak valid.';
  end if;

  if p_group_kind not in ('sator_main', 'spv_leader') then
    raise exception 'Jenis grup sistem tidak valid.';
  end if;

  update public.chat_rooms
  set
    room_type = p_room_type,
    name = coalesce(nullif(trim(p_name), ''), name),
    description = coalesce(p_description, description),
    sator_id = case when p_group_kind = 'sator_main' then p_owner_user_id else null end,
    is_active = p_is_active,
    group_mode = 'system',
    system_group_kind = p_group_kind,
    system_owner_user_id = p_owner_user_id,
    managed_by_admin = true,
    updated_at = now()
  where id = p_room_id;

  perform public.sync_system_chat_group_members(p_room_id);

  return p_room_id;
end;
$$;

grant execute on function public.reclassify_system_chat_group(uuid, text, text, uuid, text, text, boolean) to authenticated;

create or replace function public.get_sator_report_request_store_scope(
  p_sator_id uuid
)
returns table (
  store_id uuid,
  store_name text,
  promotor_count integer,
  room_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return query
  with latest_assignment as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      aps.store_id
    from public.assignments_promotor_store aps
    where aps.active = true
    order by aps.promotor_id, aps.created_at desc, aps.store_id
  ),
  roster as (
    select
      la.store_id,
      count(*)::int as promotor_count
    from public.hierarchy_sator_promotor hsp
    join latest_assignment la
      on la.promotor_id = hsp.promotor_id
    where hsp.sator_id = p_sator_id
      and hsp.active = true
    group by la.store_id
  )
  select
    st.id as store_id,
    st.store_name::text,
    rs.promotor_count,
    cr.id as room_id
  from roster rs
  join public.stores st
    on st.id = rs.store_id
  left join public.chat_rooms cr
    on cr.store_id = st.id
   and cr.room_type = 'toko'
   and cr.is_active = true
  order by st.store_name;
end;
$$;

grant execute on function public.get_sator_report_request_store_scope(uuid) to authenticated;

create or replace function public.get_spv_leader_request_rooms(
  p_spv_id uuid
)
returns table (
  room_id uuid,
  room_name text,
  room_description text,
  member_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_spv_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return query
  select
    cr.id as room_id,
    cr.name::text as room_name,
    coalesce(cr.description, '')::text as room_description,
    coalesce((
      select count(*)::int
      from public.chat_members cm
      where cm.room_id = cr.id
        and cm.left_at is null
    ), 0) as member_count
  from public.chat_rooms cr
  where cr.group_mode = 'system'
    and cr.system_group_kind = 'spv_leader'
    and cr.system_owner_user_id = p_spv_id
    and cr.is_active = true
  order by cr.created_at desc, cr.name;
end;
$$;

grant execute on function public.get_spv_leader_request_rooms(uuid) to authenticated;

create or replace function public.set_chat_group_active_admin(
  p_room_id uuid,
  p_is_active boolean
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

  update public.chat_rooms
  set
    is_active = p_is_active,
    updated_at = now()
  where id = p_room_id;
end;
$$;

grant execute on function public.set_chat_group_active_admin(uuid, boolean) to authenticated;

create or replace function public.delete_chat_group_admin(
  p_room_id uuid
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

  delete from public.chat_rooms
  where id = p_room_id;
end;
$$;

grant execute on function public.delete_chat_group_admin(uuid) to authenticated;

create or replace function public._sync_sator_system_groups(
  p_sator_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
begin
  if p_sator_id is null then
    return;
  end if;

  for v_room_id in
    select cr.id
    from public.chat_rooms cr
    where cr.group_mode = 'system'
      and cr.system_group_kind = 'sator_main'
      and cr.system_owner_user_id = p_sator_id
  loop
    perform public.sync_system_chat_group_members(v_room_id);
  end loop;
end;
$$;

create or replace function public._sync_spv_system_groups(
  p_spv_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room_id uuid;
begin
  if p_spv_id is null then
    return;
  end if;

  for v_room_id in
    select cr.id
    from public.chat_rooms cr
    where cr.group_mode = 'system'
      and cr.system_group_kind = 'spv_leader'
      and cr.system_owner_user_id = p_spv_id
  loop
    perform public.sync_system_chat_group_members(v_room_id);
  end loop;
end;
$$;

create or replace function public.on_hierarchy_sator_system_group_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public._sync_sator_system_groups(old.sator_id);
    return old;
  end if;

  perform public._sync_sator_system_groups(new.sator_id);

  if tg_op = 'UPDATE' and old.sator_id is distinct from new.sator_id then
    perform public._sync_sator_system_groups(old.sator_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trigger_sync_sator_system_groups on public.hierarchy_sator_promotor;
create trigger trigger_sync_sator_system_groups
after insert or update or delete on public.hierarchy_sator_promotor
for each row execute function public.on_hierarchy_sator_system_group_sync();

create or replace function public.on_hierarchy_spv_system_group_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public._sync_sator_system_groups(old.sator_id);
    perform public._sync_spv_system_groups(old.spv_id);
    return old;
  end if;

  perform public._sync_sator_system_groups(new.sator_id);
  perform public._sync_spv_system_groups(new.spv_id);

  if tg_op = 'UPDATE' then
    if old.sator_id is distinct from new.sator_id then
      perform public._sync_sator_system_groups(old.sator_id);
    end if;
    if old.spv_id is distinct from new.spv_id then
      perform public._sync_spv_system_groups(old.spv_id);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trigger_sync_spv_system_groups on public.hierarchy_spv_sator;
create trigger trigger_sync_spv_system_groups
after insert or update or delete on public.hierarchy_spv_sator
for each row execute function public.on_hierarchy_spv_system_group_sync();

create or replace function public.get_chat_report_request_payload(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb := '{}'::jsonb;
begin
  select jsonb_build_object(
    'request_id', req.id,
    'request_type', req.request_type,
    'room_id', req.room_id,
    'store_id', cr.store_id,
    'title', req.title,
    'note', req.note,
    'fields', coalesce(req.field_schema, '[]'::jsonb),
    'created_at', req.created_at,
    'created_by', coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'User')),
    'room_name', coalesce(cr.name, 'Grup'),
    'promotors', case
      when req.request_type = 'sator_to_store' then coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'user_id', mem.user_id,
            'name', coalesce(nullif(trim(um.nickname), ''), coalesce(um.full_name, 'Promotor'))
          )
          order by coalesce(nullif(trim(um.nickname), ''), coalesce(um.full_name, 'Promotor'))
        )
        from public.chat_members mem
        join public.users um on um.id = mem.user_id
        where mem.room_id = req.room_id
          and mem.left_at is null
          and um.role = 'promotor'
      ), '[]'::jsonb)
      else '[]'::jsonb
    end,
    'responses', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'submission_key', sub.submission_key,
          'responder_user_id', sub.responder_user_id,
          'responder_name', coalesce(nullif(trim(ru.nickname), ''), coalesce(ru.full_name, 'User')),
          'updated_at', sub.updated_at,
          'responses', sub.responses
        )
        order by sub.updated_at desc
      )
      from public.chat_report_submissions sub
      left join public.users ru on ru.id = sub.responder_user_id
      where sub.request_id = req.id
    ), '[]'::jsonb)
  )
  into v_payload
  from public.chat_report_requests req
  join public.chat_rooms cr on cr.id = req.room_id
  join public.users u on u.id = req.created_by
  where req.id = p_request_id;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_chat_report_request_payload(uuid) to authenticated;

create or replace function public._build_chat_report_message_content(
  p_request_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  return 'report_request_card::' || public.get_chat_report_request_payload(p_request_id)::text;
end;
$$;

create or replace function public.refresh_chat_report_request_message(
  p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id uuid;
begin
  select req.message_id
  into v_message_id
  from public.chat_report_requests req
  where req.id = p_request_id;

  if v_message_id is null then
    return;
  end if;

  update public.chat_messages
  set
    content = public._build_chat_report_message_content(p_request_id),
    is_edited = true,
    edited_at = now()
  where id = v_message_id;
end;
$$;

create or replace function public.create_chat_report_request(
  p_room_id uuid,
  p_request_type text,
  p_title text,
  p_note text default '',
  p_field_schema jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text := '';
  v_room public.chat_rooms%rowtype;
  v_request_id uuid;
  v_message_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_room
  from public.chat_rooms
  where id = p_room_id
    and is_active = true;

  if v_room.id is null then
    raise exception 'Grup chat tidak ditemukan.';
  end if;

  if not public.is_room_member(p_room_id, v_actor_id) then
    raise exception 'User is not a member of this room';
  end if;

  select lower(coalesce(role::text, ''))
  into v_actor_role
  from public.users
  where id = v_actor_id;

  if p_request_type = 'spv_to_sator' then
    if v_actor_role <> 'spv' then
      raise exception 'Hanya SPV yang bisa mengirim permintaan laporan ini.';
    end if;
    if v_room.room_type <> 'leader' or v_room.system_group_kind <> 'spv_leader' then
      raise exception 'Permintaan laporan SPV hanya bisa dikirim ke grup leader.';
    end if;
  elsif p_request_type = 'sator_to_store' then
    if v_actor_role <> 'sator' then
      raise exception 'Hanya SATOR yang bisa mengirim permintaan laporan ini.';
    end if;
    if v_room.room_type <> 'toko' then
      raise exception 'Permintaan laporan promotor hanya bisa dikirim ke grup toko.';
    end if;
  else
    raise exception 'Jenis permintaan laporan tidak valid.';
  end if;

  insert into public.chat_report_requests (
    room_id,
    request_type,
    title,
    note,
    field_schema,
    created_by
  )
  values (
    p_room_id,
    p_request_type,
    trim(p_title),
    coalesce(p_note, ''),
    coalesce(p_field_schema, '[]'::jsonb),
    v_actor_id
  )
  returning id into v_request_id;

  insert into public.chat_messages (
    room_id,
    sender_id,
    message_type,
    content
  )
  values (
    p_room_id,
    v_actor_id,
    'text',
    public._build_chat_report_message_content(v_request_id)
  )
  returning id into v_message_id;

  update public.chat_report_requests
  set message_id = v_message_id
  where id = v_request_id;

  update public.chat_rooms
  set updated_at = now()
  where id = p_room_id;

  update public.chat_members
  set last_read_at = now()
  where room_id = p_room_id
    and user_id = v_actor_id;

  return v_request_id;
end;
$$;

grant execute on function public.create_chat_report_request(uuid, text, text, text, jsonb) to authenticated;

create or replace function public.submit_chat_report_response(
  p_request_id uuid,
  p_responses jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text := '';
  v_request public.chat_report_requests%rowtype;
  v_submission_key text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_request
  from public.chat_report_requests
  where id = p_request_id
    and status = 'active';

  if v_request.id is null then
    raise exception 'Permintaan laporan tidak ditemukan.';
  end if;

  if not public.is_room_member(v_request.room_id, v_actor_id) then
    raise exception 'User is not a member of this room';
  end if;

  select lower(coalesce(role::text, ''))
  into v_actor_role
  from public.users
  where id = v_actor_id;

  if v_request.request_type = 'spv_to_sator' then
    if v_actor_role <> 'sator' then
      raise exception 'Hanya SATOR yang bisa mengisi laporan ini.';
    end if;
    v_submission_key := v_actor_id::text;
  elsif v_request.request_type = 'sator_to_store' then
    if v_actor_role <> 'promotor' then
      raise exception 'Hanya promotor yang bisa mengisi laporan ini.';
    end if;
    v_submission_key := 'shared_room';
  else
    raise exception 'Jenis permintaan laporan tidak valid.';
  end if;

  insert into public.chat_report_submissions (
    request_id,
    submission_key,
    responder_user_id,
    responses
  )
  values (
    p_request_id,
    v_submission_key,
    v_actor_id,
    coalesce(p_responses, '{}'::jsonb)
  )
  on conflict (request_id, submission_key) do update
  set
    responder_user_id = excluded.responder_user_id,
    responses = excluded.responses,
    updated_at = now();

  perform public.refresh_chat_report_request_message(p_request_id);

  return public.get_chat_report_request_payload(p_request_id);
end;
$$;

grant execute on function public.submit_chat_report_response(uuid, jsonb) to authenticated;
