create or replace function public.add_schedule_review_comment(
  p_promotor_id uuid,
  p_month_year text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_has_access boolean := false;
  v_message text := nullif(trim(coalesce(p_message, '')), '');
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  if p_promotor_id is null or nullif(trim(coalesce(p_month_year, '')), '') is null then
    return jsonb_build_object('success', false, 'message', 'Promotor dan bulan wajib diisi.');
  end if;

  if v_message is null then
    return jsonb_build_object('success', false, 'message', 'Komentar tidak boleh kosong.');
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    return jsonb_build_object('success', false, 'message', 'User tidak ditemukan.');
  end if;

  if v_actor.role = 'sator' then
    select exists (
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = v_actor_id
        and hsp.active = true
        and hsp.promotor_id = p_promotor_id
    )
    into v_has_access;
  elsif v_actor.role = 'spv' then
    select exists (
      select 1
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
        and hsp.active = true
        and hsp.promotor_id = p_promotor_id
    )
    into v_has_access;
  end if;

  if not v_has_access then
    return jsonb_build_object('success', false, 'message', 'Anda tidak punya akses ke jadwal ini.');
  end if;

  insert into public.schedule_review_comments (
    promotor_id,
    month_year,
    author_id,
    author_name,
    author_role,
    message
  )
  values (
    p_promotor_id,
    p_month_year,
    v_actor_id,
    coalesce(v_actor.full_name, 'User'),
    coalesce(v_actor.role::text, 'user'),
    v_message
  );

  return jsonb_build_object('success', true, 'message', 'Komentar berhasil dikirim.');
end;
$$;

grant execute on function public.add_schedule_review_comment(uuid, text, text) to authenticated;

create or replace function public.get_my_profile_snapshot()
returns jsonb
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

  return coalesce((
    select jsonb_build_object(
      'id', u.id,
      'full_name', coalesce(u.full_name, 'User'),
      'role', coalesce(u.role::text, 'user'),
      'area', coalesce(u.area, '-'),
      'avatar_url', coalesce(u.avatar_url, '')
    )
    from public.users u
    where u.id = v_actor_id
  ), '{}'::jsonb);
end;
$$;

grant execute on function public.get_my_profile_snapshot() to authenticated;
