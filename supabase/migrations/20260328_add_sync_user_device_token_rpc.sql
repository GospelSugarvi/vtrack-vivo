create or replace function public.sync_user_device_token(
  p_fcm_token text,
  p_platform text,
  p_device_label text default null,
  p_app_version text default null
)
returns public.user_device_tokens
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.user_device_tokens;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if coalesce(trim(p_fcm_token), '') = '' then
    raise exception 'FCM token is required';
  end if;

  insert into public.user_device_tokens (
    user_id,
    platform,
    fcm_token,
    device_label,
    app_version,
    is_active,
    last_seen_at
  )
  values (
    v_user_id,
    coalesce(nullif(trim(p_platform), ''), 'unknown'),
    trim(p_fcm_token),
    nullif(trim(coalesce(p_device_label, '')), ''),
    nullif(trim(coalesce(p_app_version, '')), ''),
    true,
    now()
  )
  on conflict (fcm_token) do update
  set user_id = excluded.user_id,
      platform = excluded.platform,
      device_label = excluded.device_label,
      app_version = excluded.app_version,
      is_active = true,
      last_seen_at = now(),
      updated_at = now()
  returning *
  into v_row;

  update public.user_device_tokens
  set is_active = false,
      last_seen_at = now(),
      updated_at = now()
  where user_id = v_user_id
    and platform = coalesce(nullif(trim(p_platform), ''), 'unknown')
    and fcm_token <> trim(p_fcm_token);

  return v_row;
end;
$$;

grant execute on function public.sync_user_device_token(text, text, text, text)
to authenticated;
