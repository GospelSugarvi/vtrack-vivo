create or replace function public.generate_unique_username(
  p_email text,
  p_full_name text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_candidate text;
  v_suffix text;
begin
  v_base := coalesce(nullif(trim(p_full_name), ''), split_part(coalesce(p_email, ''), '@', 1), 'user');
  v_base := lower(regexp_replace(v_base, '[^a-z0-9]+', '_', 'g'));
  v_base := trim(both '_' from v_base);
  if v_base = '' then
    v_base := 'user';
  end if;

  v_candidate := v_base;
  while exists (select 1 from public.users u where u.username = v_candidate) loop
    v_suffix := substr(md5(random()::text || clock_timestamp()::text), 1, 6);
    v_candidate := v_base || '_' || v_suffix;
  end loop;

  return v_candidate;
end;
$$;

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
  v_username text;
begin
  if exists (select 1 from public.users where id = new.id) then
    return new;
  end if;

  v_username := public.generate_unique_username(v_email, v_full_name);

  insert into public.users (
    id,
    email,
    username,
    full_name,
    nickname,
    role,
    area,
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
    'promotor',
    null,
    'active',
    'training',
    'training',
    0,
    now(),
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists trigger_on_auth_user_created_sync_profile on auth.users;
create trigger trigger_on_auth_user_created_sync_profile
after insert on auth.users
for each row execute function public.on_auth_user_created_sync_profile();

-- Backfill auth users without profile row (if any)
insert into public.users (
  id,
  email,
  username,
  full_name,
  nickname,
  role,
  area,
  status,
  promotor_status,
  promotor_type,
  base_salary,
  created_at,
  updated_at
)
select
  au.id,
  lower(coalesce(au.email, '')) as email,
  public.generate_unique_username(
    lower(coalesce(au.email, '')),
    coalesce(au.raw_user_meta_data ->> 'full_name', split_part(coalesce(au.email, ''), '@', 1))
  ) as username,
  coalesce(au.raw_user_meta_data ->> 'full_name', split_part(coalesce(au.email, ''), '@', 1)) as full_name,
  coalesce(au.raw_user_meta_data ->> 'nickname', coalesce(au.raw_user_meta_data ->> 'full_name', split_part(coalesce(au.email, ''), '@', 1))) as nickname,
  'promotor'::public.user_role,
  null,
  'active',
  'training',
  'training',
  0,
  now(),
  now()
from auth.users au
left join public.users u on u.id = au.id
where u.id is null;
