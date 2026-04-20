create or replace function public.claim_registered_user_email(
  p_user_id uuid,
  p_role text,
  p_email text,
  p_whatsapp_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := lower(coalesce(trim(p_role), ''));
  v_email text := lower(trim(coalesce(p_email, '')));
  v_phone text := regexp_replace(coalesce(p_whatsapp_phone, ''), '\\D', '', 'g');
  v_user public.users%rowtype;
  v_existing_auth_id uuid;
  v_existing_public_id uuid;
begin
  if p_user_id is null then
    raise exception 'User tidak valid';
  end if;

  if v_email = '' or position('@' in v_email) <= 1 then
    raise exception 'Email tidak valid';
  end if;

  select * into v_user
  from public.users u
  where u.id = p_user_id
    and u.deleted_at is null
    and coalesce(u.status, 'active') = 'active'
  limit 1;

  if not found then
    raise exception 'User tidak ditemukan';
  end if;

  if v_role = '' or v_user.role::text <> v_role then
    raise exception 'Role user tidak sesuai';
  end if;

  if v_phone <> '' then
    if regexp_replace(coalesce(v_user.whatsapp_phone, ''), '\\D', '', 'g') <> v_phone then
      raise exception 'Nomor telepon tidak sesuai data sistem';
    end if;
  end if;

  select au.id into v_existing_auth_id
  from auth.users au
  where lower(coalesce(au.email, '')) = v_email
    and au.id <> p_user_id
  limit 1;

  if v_existing_auth_id is not null then
    raise exception 'Email sudah dipakai akun lain';
  end if;

  select u.id into v_existing_public_id
  from public.users u
  where lower(coalesce(u.email, '')) = v_email
    and u.id <> p_user_id
    and u.deleted_at is null
  limit 1;

  if v_existing_public_id is not null then
    raise exception 'Email sudah dipakai user lain';
  end if;

  update public.users
  set
    email = v_email,
    updated_at = now()
  where id = p_user_id;

  update auth.users
  set
    email = v_email,
    raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('email', v_email)
  where id = p_user_id;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'email', v_email
  );
end;
$$;

grant execute on function public.claim_registered_user_email(uuid, text, text, text) to anon, authenticated;
