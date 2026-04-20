create or replace function public.save_monthly_schedule_draft(
  p_schedule_date date,
  p_shift_type text,
  p_month_year text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_current_status text;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if p_schedule_date is null or nullif(trim(coalesce(p_shift_type, '')), '') is null or nullif(trim(coalesce(p_month_year, '')), '') is null then
    raise exception 'Data jadwal tidak lengkap';
  end if;

  select s.status
    into v_current_status
  from public.schedules s
  where s.promotor_id = v_user_id
    and s.schedule_date = p_schedule_date
  limit 1;

  if coalesce(v_current_status, 'draft') = 'submitted' then
    raise exception 'Jadwal submitted tidak bisa diedit';
  end if;

  insert into public.schedules (
    promotor_id,
    schedule_date,
    shift_type,
    status,
    month_year,
    rejection_reason
  ) values (
    v_user_id,
    p_schedule_date,
    trim(p_shift_type),
    'draft',
    trim(p_month_year),
    null
  )
  on conflict (promotor_id, schedule_date)
  do update set
    shift_type = excluded.shift_type,
    status = 'draft',
    month_year = excluded.month_year,
    rejection_reason = null,
    updated_at = now();

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.save_monthly_schedule_draft_bulk(
  p_month_year text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_item jsonb;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_month_year, '')), '') is null then
    raise exception 'Bulan jadwal wajib diisi';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Item jadwal kosong';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop
    perform public.save_monthly_schedule_draft(
      nullif(v_item->>'schedule_date', '')::date,
      v_item->>'shift_type',
      p_month_year
    );
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'success', true,
    'saved_count', v_count
  );
end;
$$;

create or replace function public.replace_monthly_schedule_from_previous(
  p_target_month text
)
returns table(success boolean, message text, copied_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_target_month, '')), '') is null then
    raise exception 'Target bulan wajib diisi';
  end if;

  delete from public.schedules
  where promotor_id = v_user_id
    and month_year = trim(p_target_month)
    and status in ('draft', 'rejected');

  return query
  select *
  from public.copy_previous_month_schedule(v_user_id, trim(p_target_month));
end;
$$;

create or replace function public.post_schedule_review_comment(
  p_month_year text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_author_name text;
  v_comment_id uuid;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_month_year, '')), '') is null or nullif(trim(coalesce(p_message, '')), '') is null then
    raise exception 'Komentar tidak boleh kosong';
  end if;

  select coalesce(nullif(trim(u.full_name), ''), nullif(trim(u.nickname), ''), 'Promotor')
    into v_author_name
  from public.users u
  where u.id = v_user_id;

  insert into public.schedule_review_comments (
    promotor_id,
    month_year,
    author_id,
    author_name,
    author_role,
    message
  ) values (
    v_user_id,
    trim(p_month_year),
    v_user_id,
    coalesce(v_author_name, 'Promotor'),
    'promotor',
    trim(p_message)
  )
  returning id into v_comment_id;

  return jsonb_build_object(
    'success', true,
    'comment_id', v_comment_id
  );
end;
$$;

create or replace function public.delete_promotor_imei_normalization_draft(
  p_normalization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_deleted_id uuid;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if p_normalization_id is null then
    raise exception 'Item IMEI tidak valid';
  end if;

  delete from public.imei_normalizations i
  where i.id = p_normalization_id
    and i.promotor_id = v_user_id
    and i.status in ('pending', 'reported')
    and i.sent_to_sator_at is null
  returning i.id into v_deleted_id;

  if v_deleted_id is null then
    raise exception 'Hanya draft IMEI yang belum dikirim yang bisa dihapus';
  end if;

  return jsonb_build_object(
    'success', true,
    'normalization_id', v_deleted_id
  );
end;
$$;

grant execute on function public.save_monthly_schedule_draft(date, text, text) to authenticated;
grant execute on function public.save_monthly_schedule_draft_bulk(text, jsonb) to authenticated;
grant execute on function public.replace_monthly_schedule_from_previous(text) to authenticated;
grant execute on function public.post_schedule_review_comment(text, text) to authenticated;
grant execute on function public.delete_promotor_imei_normalization_draft(uuid) to authenticated;
