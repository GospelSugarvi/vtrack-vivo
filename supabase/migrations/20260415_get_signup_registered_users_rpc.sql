create or replace function public.get_signup_registered_users(
  p_role text default 'promotor'
)
returns table (
  user_id uuid,
  full_name text,
  nickname text,
  email text,
  whatsapp_phone text,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(coalesce(trim(p_role), 'promotor'));
begin
  return query
  select
    u.id as user_id,
    u.full_name,
    coalesce(nullif(trim(u.nickname), ''), u.full_name) as nickname,
    lower(coalesce(u.email, '')) as email,
    coalesce(u.whatsapp_phone, '') as whatsapp_phone,
    u.role::text as role
  from public.users u
  where u.deleted_at is null
    and coalesce(u.status, 'active') = 'active'
    and u.role::text = v_role
  order by u.full_name;
end;
$$;

grant execute on function public.get_signup_registered_users(text) to anon, authenticated;
