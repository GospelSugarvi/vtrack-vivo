create or replace function public.refresh_store_chat_scope(p_store_id uuid)
returns void
language plpgsql
security definer
as $function$
declare
  v_room_id uuid;
  v_store_name text;
begin
  select id
  into v_room_id
  from public.chat_rooms
  where store_id = p_store_id
    and room_type = 'toko'
  limit 1;

  if v_room_id is null then
    select store_name
    into v_store_name
    from public.stores
    where id = p_store_id;

    insert into public.chat_rooms (room_type, name, store_id, is_active)
    values ('toko', 'Toko: ' || coalesce(v_store_name, 'Unknown'), p_store_id, true)
    returning id into v_room_id;
  end if;

  with scoped_users as (
    select distinct aps.promotor_id as user_id
    from public.assignments_promotor_store aps
    where aps.store_id = p_store_id
      and aps.active = true

    union

    select distinct hsp.sator_id as user_id
    from public.assignments_promotor_store aps
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    where aps.store_id = p_store_id
      and aps.active = true

    union

    select distinct hss.spv_id as user_id
    from public.assignments_promotor_store aps
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    join public.hierarchy_spv_sator hss
      on hss.sator_id = hsp.sator_id
     and hss.active = true
    where aps.store_id = p_store_id
      and aps.active = true
  )
  insert into public.chat_members (room_id, user_id)
  select v_room_id, su.user_id
  from scoped_users su
  on conflict (room_id, user_id) do update
  set left_at = null;

  with scoped_users as (
    select distinct aps.promotor_id as user_id
    from public.assignments_promotor_store aps
    where aps.store_id = p_store_id
      and aps.active = true

    union

    select distinct hsp.sator_id as user_id
    from public.assignments_promotor_store aps
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    where aps.store_id = p_store_id
      and aps.active = true

    union

    select distinct hss.spv_id as user_id
    from public.assignments_promotor_store aps
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    join public.hierarchy_spv_sator hss
      on hss.sator_id = hsp.sator_id
     and hss.active = true
    where aps.store_id = p_store_id
      and aps.active = true
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
$function$;

create or replace function public.on_store_assignment_sync_chat()
returns trigger
language plpgsql
security definer
as $function$
begin
  perform public.refresh_store_chat_scope(new.store_id);
  return new;
end;
$function$;

create or replace function public.on_hierarchy_sator_sync_chat()
returns trigger
language plpgsql
security definer
as $function$
declare
  v_room_id uuid;
  v_full_name text;
  v_store_id uuid;
begin
  select full_name into v_full_name from public.users where id = new.sator_id;
  select id into v_room_id from public.chat_rooms where sator_id = new.sator_id and room_type = 'tim' limit 1;

  if v_room_id is null then
    insert into public.chat_rooms (room_type, name, sator_id, is_active)
    values ('tim', 'Tim SATOR: ' || coalesce(v_full_name, 'Unknown'), new.sator_id, true)
    returning id into v_room_id;
  end if;

  perform public.sync_chat_member(v_room_id, new.sator_id);
  if tg_op = 'INSERT' or (tg_op = 'UPDATE' and new.active = true) then
    perform public.sync_chat_member(v_room_id, new.promotor_id);
  elsif tg_op = 'UPDATE' and new.active = false then
    perform public.unsync_chat_member(v_room_id, new.promotor_id);
  end if;

  for v_store_id in
    select distinct aps.store_id
    from public.assignments_promotor_store aps
    where aps.promotor_id = new.promotor_id
      and aps.active = true
  loop
    perform public.refresh_store_chat_scope(v_store_id);
  end loop;

  return new;
end;
$function$;

create or replace function public.on_hierarchy_spv_sync_store_chat()
returns trigger
language plpgsql
security definer
as $function$
declare
  v_store_id uuid;
begin
  for v_store_id in
    select distinct aps.store_id
    from public.assignments_promotor_store aps
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = aps.promotor_id
     and hsp.active = true
    where hsp.sator_id = new.sator_id
      and aps.active = true
  loop
    perform public.refresh_store_chat_scope(v_store_id);
  end loop;

  return new;
end;
$function$;

drop trigger if exists trigger_sync_spv_store_chat_hierarchy on public.hierarchy_spv_sator;
create trigger trigger_sync_spv_store_chat_hierarchy
after insert or update on public.hierarchy_spv_sator
for each row execute function public.on_hierarchy_spv_sync_store_chat();

create or replace function public.initial_chat_sync()
returns void
language plpgsql
security definer
as $function$
declare
  r record;
  v_global_id uuid;
  v_announcement_id uuid;
begin
  select id into v_global_id from public.chat_rooms where room_type = 'global' limit 1;
  select id into v_announcement_id from public.chat_rooms where room_type = 'announcement' limit 1;

  for r in select id from public.users where deleted_at is null loop
    if v_global_id is not null then
      perform public.sync_chat_member(v_global_id, r.id);
    end if;
    if v_announcement_id is not null then
      perform public.sync_chat_member(v_announcement_id, r.id);
    end if;
  end loop;

  for r in
    select distinct store_id
    from public.assignments_promotor_store
    where active = true
  loop
    perform public.refresh_store_chat_scope(r.store_id);
  end loop;

  for r in
    select sator_id, promotor_id
    from public.hierarchy_sator_promotor
    where active = true
  loop
    update public.hierarchy_sator_promotor
    set created_at = now()
    where sator_id = r.sator_id
      and promotor_id = r.promotor_id;
  end loop;

  for r in
    select spv_id, sator_id
    from public.hierarchy_spv_sator
    where active = true
  loop
    update public.hierarchy_spv_sator
    set created_at = now()
    where spv_id = r.spv_id
      and sator_id = r.sator_id;
  end loop;
end;
$function$;

select public.initial_chat_sync();
