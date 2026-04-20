create or replace function public.get_schedule_detail_snapshot(
  p_promotor_id uuid,
  p_month_year text
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
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    raise exception 'User profile not found';
  end if;

  if v_actor.role = 'admin'::public.user_role or public.is_elevated_user() then
    v_has_access := true;
  elsif v_actor.role = 'promotor'::public.user_role then
    v_has_access := p_promotor_id = v_actor_id;
  elsif v_actor.role = 'sator'::public.user_role then
    select exists(
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = v_actor_id
        and hsp.promotor_id = p_promotor_id
        and hsp.active = true
    )
    into v_has_access;
  elsif v_actor.role = 'spv'::public.user_role then
    select exists(
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
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'current_user', jsonb_build_object(
      'id', v_actor.id,
      'full_name', coalesce(v_actor.full_name, 'User'),
      'role', coalesce(v_actor.role::text, '')
    ),
    'schedules', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.schedule_date)
      from public.get_promotor_schedule_detail(p_promotor_id, p_month_year) s
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'author_id', c.author_id,
          'author_name', c.author_name,
          'author_role', c.author_role,
          'message', c.message,
          'created_at', c.created_at
        )
        order by c.created_at
      )
      from public.schedule_review_comments c
      where c.promotor_id = p_promotor_id
        and c.month_year = p_month_year
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_schedule_detail_snapshot(uuid, text) to authenticated;

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
  v_message text := nullif(trim(coalesce(p_message, '')), '');
  v_has_access boolean := false;
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  if v_message is null then
    return jsonb_build_object('success', false, 'message', 'Komentar tidak boleh kosong.');
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Profil user tidak ditemukan.');
  end if;

  if v_actor.role = 'admin'::public.user_role or public.is_elevated_user() then
    v_has_access := true;
  elsif v_actor.role = 'promotor'::public.user_role then
    v_has_access := p_promotor_id = v_actor_id;
  elsif v_actor.role = 'sator'::public.user_role then
    select exists(
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = v_actor_id
        and hsp.promotor_id = p_promotor_id
        and hsp.active = true
    )
    into v_has_access;
  elsif v_actor.role = 'spv'::public.user_role then
    select exists(
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

create or replace function public.review_monthly_schedule_with_comment(
  p_promotor_id uuid,
  p_month_year text,
  p_action text,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_result record;
  v_reason text := nullif(trim(coalesce(p_rejection_reason, '')), '');
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found or v_actor.role IS DISTINCT FROM 'sator'::public.user_role then
    return jsonb_build_object('success', false, 'message', 'Hanya sator yang dapat mereview jadwal.');
  end if;

  select *
  into v_result
  from public.review_monthly_schedule(
    v_actor_id,
    p_promotor_id,
    p_month_year,
    p_action,
    v_reason
  )
  limit 1;

  if coalesce(v_result.success, false) <> true then
    return jsonb_build_object(
      'success', false,
      'message', coalesce(v_result.message, 'Review jadwal gagal.')
    );
  end if;

  if p_action = 'reject' and v_reason is not null then
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
      coalesce(v_actor.full_name, 'SATOR'),
      coalesce(v_actor.role::text, 'sator'),
      v_reason
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'message', coalesce(v_result.message, 'Proses review selesai.')
  );
end;
$$;

grant execute on function public.review_monthly_schedule_with_comment(uuid, text, text, text) to authenticated;
