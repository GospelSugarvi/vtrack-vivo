create or replace function public.submit_monthly_schedule(
  p_promotor_id uuid,
  p_month_year text
)
returns table (
  success boolean,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule_count integer;
  v_updated_count integer;
  v_promotor_name text := 'Promotor';
  v_sator_id uuid;
begin
  select count(*)
  into v_schedule_count
  from public.schedules
  where promotor_id = p_promotor_id
    and month_year = p_month_year;

  if v_schedule_count = 0 then
    return query select false, 'No schedules found for this month.';
    return;
  end if;

  update public.schedules
  set status = 'submitted',
      updated_at = now()
  where promotor_id = p_promotor_id
    and month_year = p_month_year
    and status = 'draft';

  get diagnostics v_updated_count = row_count;

  if v_updated_count = 0 then
    return query select false, 'Tidak ada jadwal draft yang bisa dikirim.';
    return;
  end if;

  select coalesce(u.full_name, 'Promotor')
  into v_promotor_name
  from public.users u
  where u.id = p_promotor_id;

  for v_sator_id in
    select distinct hsp.sator_id
    from public.hierarchy_sator_promotor hsp
    where hsp.promotor_id = p_promotor_id
      and hsp.active = true
      and hsp.sator_id is not null
  loop
    perform public.create_app_notification(
      p_recipient_user_id := v_sator_id,
      p_actor_user_id := p_promotor_id,
      p_role_target := 'sator',
      p_category := 'approval',
      p_type := 'monthly_schedule_submitted',
      p_title := 'Jadwal bulanan menunggu review',
      p_body := format(
        '%s mengirim jadwal bulanan %s untuk direview.',
        v_promotor_name,
        p_month_year
      ),
      p_entity_type := 'monthly_schedule',
      p_entity_id := format('%s:%s', p_promotor_id, p_month_year),
      p_action_route := '/sator/jadwal',
      p_action_params := jsonb_build_object(
        'promotor_id', p_promotor_id,
        'month_year', p_month_year
      ),
      p_payload := jsonb_build_object(
        'promotor_id', p_promotor_id,
        'month_year', p_month_year,
        'status', 'submitted'
      ),
      p_priority := 'high',
      p_dedupe_key := format(
        'monthly_schedule_submitted:%s:%s:%s',
        p_promotor_id,
        p_month_year,
        v_sator_id
      )
    );
  end loop;

  return query select true, 'Schedule submitted successfully for approval.';
end;
$$;

create or replace function public.review_monthly_schedule(
  p_sator_id uuid,
  p_promotor_id uuid,
  p_month_year text,
  p_action text,
  p_rejection_reason text default null
)
returns table (
  success boolean,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_status text;
  v_has_access boolean;
  v_submitted_count integer;
begin
  select exists (
    select 1
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.promotor_id = p_promotor_id
      and hsp.active = true
  ) into v_has_access;

  if not v_has_access then
    return query select false, 'Kamu tidak punya akses ke promotor ini.';
    return;
  end if;

  if p_action = 'approve' then
    v_new_status := 'approved';
  elsif p_action = 'reject' then
    v_new_status := 'rejected';
    if p_rejection_reason is null or trim(p_rejection_reason) = '' then
      return query select false, 'Alasan penolakan wajib diisi.';
      return;
    end if;
  else
    return query select false, 'Aksi tidak valid.';
    return;
  end if;

  select count(*)::integer
  into v_submitted_count
  from public.schedules s
  where s.promotor_id = p_promotor_id
    and s.month_year = p_month_year
    and s.status = 'submitted';

  if v_submitted_count = 0 then
    return query select false, 'Tidak ada jadwal submitted yang bisa direview.';
    return;
  end if;

  update public.schedules
  set status = v_new_status,
      rejection_reason = case
        when p_action = 'reject' then trim(p_rejection_reason)
        else null
      end,
      updated_at = now()
  where promotor_id = p_promotor_id
    and month_year = p_month_year
    and status = 'submitted';

  perform public.create_app_notification(
    p_recipient_user_id := p_promotor_id,
    p_actor_user_id := p_sator_id,
    p_role_target := 'promotor',
    p_category := 'approval',
    p_type := case
      when p_action = 'approve' then 'monthly_schedule_approved'
      else 'monthly_schedule_rejected'
    end,
    p_title := case
      when p_action = 'approve' then 'Jadwal bulanan disetujui'
      else 'Jadwal bulanan ditolak'
    end,
    p_body := case
      when p_action = 'approve' then format(
        'Jadwal bulanan %s sudah disetujui oleh SATOR.',
        p_month_year
      )
      else format(
        'Jadwal bulanan %s ditolak oleh SATOR.',
        p_month_year
      )
    end,
    p_entity_type := 'monthly_schedule',
    p_entity_id := format('%s:%s', p_promotor_id, p_month_year),
    p_action_route := '/promotor/jadwal-bulanan',
    p_action_params := jsonb_build_object(
      'promotor_id', p_promotor_id,
      'month_year', p_month_year
    ),
    p_payload := jsonb_build_object(
      'promotor_id', p_promotor_id,
      'month_year', p_month_year,
      'status', v_new_status,
      'rejection_reason', case
        when p_action = 'reject' then trim(p_rejection_reason)
        else null
      end
    ),
    p_priority := 'high',
    p_dedupe_key := format(
      'monthly_schedule_review:%s:%s:%s',
      p_promotor_id,
      p_month_year,
      v_new_status
    )
  );

  if p_action = 'approve' then
    return query select true, 'Jadwal berhasil di-approve.';
  else
    return query select true, 'Jadwal ditolak. Promotor bisa revisi lalu kirim ulang.';
  end if;
end;
$$;

create or replace function public.send_imei_to_sator(p_normalization_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
  v_sator_id uuid;
begin
  update public.imei_normalizations
  set
    status = 'reported',
    sent_to_sator_at = coalesce(sent_to_sator_at, now()),
    updated_at = now()
  where id = p_normalization_id
    and status in ('pending', 'reported');

  if not found then
    return json_build_object(
      'success', false,
      'error', 'IMEI normalization record not found or already processed'
    );
  end if;

  select
    i.id,
    i.promotor_id,
    i.store_id,
    i.imei,
    coalesce(u.full_name, 'Promotor') as promotor_name,
    coalesce(s.store_name, 'Toko') as store_name,
    coalesce(p.model_name, 'Produk') as product_name
  into v_row
  from public.imei_normalizations i
  left join public.users u on u.id = i.promotor_id
  left join public.stores s on s.id = i.store_id
  left join public.products p on p.id = i.product_id
  where i.id = p_normalization_id;

  for v_sator_id in
    (
      select distinct hsp.sator_id
      from public.hierarchy_sator_promotor hsp
      where hsp.promotor_id = v_row.promotor_id
        and hsp.active = true
        and hsp.sator_id is not null
      union
      select distinct ssa.sator_id
      from public.sator_store_assignments ssa
      where ssa.store_id = v_row.store_id
        and ssa.is_active = true
        and ssa.sator_id is not null
    )
  loop
    perform public.create_app_notification(
      p_recipient_user_id := v_sator_id,
      p_actor_user_id := v_row.promotor_id,
      p_role_target := 'sator',
      p_category := 'approval',
      p_type := 'imei_normalization_submitted',
      p_title := 'Penormalan IMEI menunggu review',
      p_body := format(
        '%s mengirim IMEI %s dari %s untuk dinormalisasi.',
        v_row.promotor_name,
        v_row.imei,
        v_row.store_name
      ),
      p_entity_type := 'imei_normalization',
      p_entity_id := v_row.id::text,
      p_action_route := '/sator/imei-normalisasi',
      p_action_params := jsonb_build_object('normalization_id', v_row.id),
      p_payload := jsonb_build_object(
        'normalization_id', v_row.id,
        'imei', v_row.imei,
        'store_name', v_row.store_name,
        'product_name', v_row.product_name,
        'status', 'reported'
      ),
      p_priority := 'high',
      p_dedupe_key := format(
        'imei_normalization_submitted:%s:%s',
        v_row.id,
        v_sator_id
      )
    );
  end loop;

  return json_build_object(
    'success', true,
    'message', 'IMEI sent to SATOR for normalization'
  );
end;
$$;

create or replace function public.mark_imei_normalized(
  p_normalization_id uuid,
  p_sator_id uuid,
  p_notes text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  update public.imei_normalizations
  set
    status = 'ready_to_scan',
    normalized_at = now(),
    sator_id = p_sator_id,
    notes = p_notes,
    updated_at = now()
  where id = p_normalization_id
    and status in ('reported', 'processing', 'sent', 'normalized', 'normal');

  if not found then
    return json_build_object(
      'success', false,
      'error', 'IMEI normalization record not found or not in processable status'
    );
  end if;

  select
    i.id,
    i.promotor_id,
    i.imei,
    coalesce(s.store_name, 'Toko') as store_name
  into v_row
  from public.imei_normalizations i
  left join public.stores s on s.id = i.store_id
  where i.id = p_normalization_id;

  perform public.create_app_notification(
    p_recipient_user_id := v_row.promotor_id,
    p_actor_user_id := p_sator_id,
    p_role_target := 'promotor',
    p_category := 'approval',
    p_type := 'imei_normalization_ready',
    p_title := 'IMEI siap discan',
    p_body := format(
      'IMEI %s dari %s sudah dinormalisasi oleh SATOR dan siap discan.',
      v_row.imei,
      v_row.store_name
    ),
    p_entity_type := 'imei_normalization',
    p_entity_id := v_row.id::text,
    p_action_route := '/promotor/imei-normalization',
    p_action_params := jsonb_build_object('normalization_id', v_row.id),
    p_payload := jsonb_build_object(
      'normalization_id', v_row.id,
      'imei', v_row.imei,
      'store_name', v_row.store_name,
      'status', 'ready_to_scan',
      'notes', p_notes
    ),
    p_priority := 'high',
    p_dedupe_key := format('imei_normalization_ready:%s', v_row.id)
  );

  return json_build_object(
    'success', true,
    'message', 'IMEI marked as normalized'
  );
end;
$$;
