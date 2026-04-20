create or replace function public.get_signup_supervisor_options(
  p_role text default 'promotor'
)
returns table (
  supervisor_id uuid,
  full_name text,
  nickname text,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(coalesce(trim(p_role), 'promotor'));
  v_supervisor_role text;
begin
  v_supervisor_role := case v_role
    when 'promotor' then 'sator'
    when 'sator' then 'spv'
    when 'spv' then 'manager'
    else null
  end;

  if v_supervisor_role is null then
    return;
  end if;

  return query
  select
    u.id as supervisor_id,
    u.full_name,
    coalesce(nullif(trim(u.nickname), ''), u.full_name) as nickname,
    u.role::text as role
  from public.users u
  where u.deleted_at is null
    and coalesce(u.status, 'active') = 'active'
    and u.role::text = v_supervisor_role
  order by u.full_name;
end;
$$;

grant execute on function public.get_signup_supervisor_options(text) to anon, authenticated;

create or replace function public.on_auth_user_created_sync_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(new.email, ''));
  v_full_name text := coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, ''), '@', 1));
  v_nickname text := coalesce(new.raw_user_meta_data ->> 'nickname', v_full_name);
  v_phone text := nullif(trim(coalesce(new.raw_user_meta_data ->> 'whatsapp_phone', '')), '');
  v_role_text text := lower(coalesce(new.raw_user_meta_data ->> 'role', 'promotor'));
  v_role public.user_role := 'promotor';
  v_username text;
  v_supervisor_id uuid;
begin
  if exists (select 1 from public.users where id = new.id) then
    return new;
  end if;

  if v_role_text in ('promotor', 'sator', 'spv', 'manager', 'admin') then
    v_role := v_role_text::public.user_role;
  end if;

  v_username := public.generate_unique_username(v_email, v_full_name);

  begin
    v_supervisor_id := nullif(new.raw_user_meta_data ->> 'supervisor_id', '')::uuid;
  exception when others then
    v_supervisor_id := null;
  end;

  insert into public.users (
    id,
    email,
    username,
    full_name,
    nickname,
    role,
    area,
    whatsapp_phone,
    status,
    promotor_status,
    promotor_type,
    base_salary,
    created_at,
    updated_at
  )
  values (
    new.id,
    v_email,
    v_username,
    v_full_name,
    v_nickname,
    v_role,
    null,
    v_phone,
    'active',
    case when v_role = 'promotor' then 'training' else null end,
    case when v_role = 'promotor' then 'training' else null end,
    0,
    now(),
    now()
  )
  on conflict (id) do nothing;

  if v_supervisor_id is not null and v_supervisor_id <> new.id then
    if v_role = 'promotor'
      and exists (
        select 1 from public.users su
        where su.id = v_supervisor_id
          and su.deleted_at is null
          and su.role = 'sator'
      )
    then
      insert into public.hierarchy_sator_promotor (sator_id, promotor_id, active)
      select v_supervisor_id, new.id, true
      where not exists (
        select 1 from public.hierarchy_sator_promotor h
        where h.sator_id = v_supervisor_id
          and h.promotor_id = new.id
          and h.active = true
      );
    elsif v_role = 'sator'
      and exists (
        select 1 from public.users su
        where su.id = v_supervisor_id
          and su.deleted_at is null
          and su.role = 'spv'
      )
    then
      insert into public.hierarchy_spv_sator (spv_id, sator_id, active)
      select v_supervisor_id, new.id, true
      where not exists (
        select 1 from public.hierarchy_spv_sator h
        where h.spv_id = v_supervisor_id
          and h.sator_id = new.id
          and h.active = true
      );
    elsif v_role = 'spv'
      and exists (
        select 1 from public.users su
        where su.id = v_supervisor_id
          and su.deleted_at is null
          and su.role = 'manager'
      )
    then
      insert into public.hierarchy_manager_spv (manager_id, spv_id, active)
      select v_supervisor_id, new.id, true
      where not exists (
        select 1 from public.hierarchy_manager_spv h
        where h.manager_id = v_supervisor_id
          and h.spv_id = new.id
          and h.active = true
      );
    end if;
  end if;

  return new;
end;
$$;
