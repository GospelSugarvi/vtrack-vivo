create or replace function public.submit_scoped_visit(
  p_store_id uuid,
  p_photo_urls jsonb,
  p_notes text default null,
  p_visit_at timestamptz default now(),
  p_target_sator_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.user_role;
  v_target_sator_id uuid;
  v_visit_date date := (p_visit_at at time zone 'Asia/Makassar')::date;
  v_first_photo text;
  v_second_photo text;
  v_row public.store_visits%rowtype;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select u.role
  into v_actor_role
  from public.users u
  where u.id = v_actor_id;

  if v_actor_role not in ('sator'::public.user_role, 'spv'::public.user_role) then
    raise exception 'Hanya sator atau spv yang dapat submit visit.';
  end if;

  if trim(coalesce(p_notes, '')) = '' then
    raise exception 'Catatan visit wajib diisi.';
  end if;

  v_target_sator_id := coalesce(p_target_sator_id, v_actor_id);

  if coalesce(jsonb_array_length(coalesce(p_photo_urls, '[]'::jsonb)), 0) <= 0 then
    raise exception 'Minimal 1 foto visit diperlukan.';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(v_target_sator_id)::jsonb, '[]'::jsonb)) as x(
      store_id uuid,
      store_name text,
      address text,
      area text,
      last_visit timestamptz,
      issue_count integer,
      priority integer,
      priority_score integer,
      priority_reasons jsonb
    )
    where x.store_id = p_store_id
  ) then
    raise exception 'Store is outside SATOR scope';
  end if;

  select value
  into v_first_photo
  from jsonb_array_elements_text(coalesce(p_photo_urls, '[]'::jsonb))
  limit 1;

  select value
  into v_second_photo
  from jsonb_array_elements_text(coalesce(p_photo_urls, '[]'::jsonb))
  offset 1
  limit 1;

  insert into public.store_visits (
    store_id,
    sator_id,
    visit_date,
    check_in_time,
    check_in_photo,
    check_out_photo,
    notes,
    follow_up
  )
  values (
    p_store_id,
    v_target_sator_id,
    v_visit_date,
    p_visit_at,
    v_first_photo,
    v_second_photo,
    trim(p_notes),
    null
  )
  returning *
  into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'visit_date', v_row.visit_date,
    'check_in_time', v_row.check_in_time
  );
end;
$$;

grant execute on function public.submit_scoped_visit(uuid, jsonb, text, timestamptz, uuid) to authenticated;
