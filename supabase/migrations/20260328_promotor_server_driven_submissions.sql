create or replace function public.submit_promotor_stock_input(
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_store_id uuid;
  v_item jsonb;
  v_imei text;
  v_variant_id uuid;
  v_tipe_stok text;
  v_product_id uuid;
  v_inserted_stok_id uuid;
  v_success_count integer := 0;
  v_duplicate_imeis text[] := '{}';
  v_failed_imeis text[] := '{}';
  v_inserted_imeis text[] := '{}';
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Item stok wajib diisi';
  end if;

  select aps.store_id
    into v_store_id
  from public.assignments_promotor_store aps
  where aps.promotor_id = v_user_id
    and aps.active = true
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    raise exception 'Akun promotor belum terhubung ke toko aktif.';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items)
  loop
    v_imei := nullif(trim(coalesce(v_item->>'imei', '')), '');
    v_variant_id := nullif(v_item->>'variant_id', '')::uuid;
    v_tipe_stok := lower(trim(coalesce(v_item->>'tipe_stok', '')));

    if v_imei is null or length(v_imei) <> 15 or v_variant_id is null or v_tipe_stok not in ('fresh', 'chip', 'display') then
      v_failed_imeis := array_append(v_failed_imeis, coalesce(v_imei, ''));
      continue;
    end if;

    begin
      select pv.product_id
        into v_product_id
      from public.product_variants pv
      where pv.id = v_variant_id;

      if v_product_id is null then
        v_failed_imeis := array_append(v_failed_imeis, v_imei);
        continue;
      end if;

      insert into public.stok (
        imei,
        store_id,
        promotor_id,
        product_id,
        variant_id,
        tipe_stok,
        is_sold,
        created_by,
        created_at,
        updated_at
      ) values (
        v_imei,
        v_store_id,
        v_user_id,
        v_product_id,
        v_variant_id,
        v_tipe_stok,
        false,
        v_user_id,
        now(),
        now()
      )
      returning id into v_inserted_stok_id;

      insert into public.stock_movement_log (
        stok_id,
        imei,
        from_store_id,
        to_store_id,
        movement_type,
        moved_by,
        moved_at,
        note
      ) values (
        v_inserted_stok_id,
        v_imei,
        null,
        v_store_id,
        'initial',
        v_user_id,
        now(),
        'Initial stock input via mobile'
      );

      v_success_count := v_success_count + 1;
      v_inserted_imeis := array_append(v_inserted_imeis, v_imei);
    exception
      when unique_violation then
        v_duplicate_imeis := array_append(v_duplicate_imeis, v_imei);
      when others then
        v_failed_imeis := array_append(v_failed_imeis, v_imei);
    end;
  end loop;

  return jsonb_build_object(
    'success_count', v_success_count,
    'duplicate_imeis', v_duplicate_imeis,
    'failed_imeis', v_failed_imeis,
    'inserted_imeis', v_inserted_imeis
  );
end;
$$;

create or replace function public.submit_promotor_stock_validation(
  p_validation_date date,
  p_stock_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_store_id uuid;
  v_validation_id uuid;
  v_selected_count integer := 0;
  v_inserted_count integer := 0;
  v_total_items integer := 0;
  v_validated_items integer := 0;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if p_validation_date is null then
    raise exception 'Tanggal validasi wajib diisi';
  end if;

  if p_stock_ids is null or coalesce(array_length(p_stock_ids, 1), 0) = 0 then
    raise exception 'Pilih minimal 1 item stok';
  end if;

  select aps.store_id
    into v_store_id
  from public.assignments_promotor_store aps
  where aps.promotor_id = v_user_id
    and aps.active = true
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    raise exception 'Toko aktif promotor tidak ditemukan';
  end if;

  v_selected_count := coalesce(array_length(p_stock_ids, 1), 0);

  insert into public.stock_validations (
    promotor_id,
    store_id,
    validation_date,
    total_items,
    validated_items,
    corrections_made,
    status,
    created_at,
    updated_at
  ) values (
    v_user_id,
    v_store_id,
    p_validation_date,
    0,
    0,
    0,
    'completed',
    now(),
    now()
  )
  on conflict (promotor_id, store_id, validation_date)
    where status = 'completed'
  do update
    set updated_at = now()
  returning id into v_validation_id;

  with selected_stock as (
    select
      s.id as stok_id,
      s.imei,
      s.tipe_stok
    from public.stok s
    where s.id = any(p_stock_ids)
      and s.store_id = v_store_id
      and coalesce(s.is_sold, false) = false
  ), inserted_rows as (
    insert into public.stock_validation_items (
      validation_id,
      stok_id,
      imei,
      original_condition,
      validated_condition,
      is_present
    )
    select
      v_validation_id,
      ss.stok_id,
      ss.imei,
      ss.tipe_stok,
      ss.tipe_stok,
      true
    from selected_stock ss
    on conflict (validation_id, stok_id) do nothing
    returning 1
  )
  select count(*) into v_inserted_count
  from inserted_rows;

  select count(*)
    into v_total_items
  from public.stok s
  where s.store_id = v_store_id
    and coalesce(s.is_sold, false) = false;

  select count(*)
    into v_validated_items
  from public.stock_validation_items svi
  where svi.validation_id = v_validation_id;

  update public.stock_validations
  set
    total_items = v_total_items,
    validated_items = v_validated_items,
    corrections_made = 0,
    status = 'completed',
    updated_at = now()
  where id = v_validation_id;

  return jsonb_build_object(
    'validation_id', v_validation_id,
    'selected_count', v_selected_count,
    'inserted_count', v_inserted_count,
    'validated_items', v_validated_items,
    'total_items', v_total_items
  );
end;
$$;

create or replace function public.submit_promotor_vast_application(
  p_application_date date,
  p_customer_name text,
  p_customer_phone text,
  p_pekerjaan text,
  p_monthly_income numeric,
  p_product_variant_id uuid,
  p_product_label text,
  p_limit_amount numeric,
  p_dp_amount numeric,
  p_tenor_months integer,
  p_outcome_status text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_store_id uuid;
  v_application_id uuid;
  v_outcome text := lower(trim(coalesce(p_outcome_status, '')));
  v_lifecycle text;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_customer_name, '')), '') is null then
    raise exception 'Nama customer wajib diisi';
  end if;

  if nullif(trim(coalesce(p_customer_phone, '')), '') is null then
    raise exception 'Nomor HP wajib diisi';
  end if;

  if nullif(trim(coalesce(p_pekerjaan, '')), '') is null then
    raise exception 'Pekerjaan wajib diisi';
  end if;

  if v_outcome not in ('acc', 'pending', 'reject') then
    raise exception 'Status hasil tidak valid';
  end if;

  select aps.store_id
    into v_store_id
  from public.assignments_promotor_store aps
  where aps.promotor_id = v_user_id
    and aps.active = true
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    raise exception 'Toko aktif promotor tidak ditemukan';
  end if;

  v_lifecycle := case
    when v_outcome = 'acc' then 'closed_direct'
    when v_outcome = 'reject' then 'rejected'
    else 'approved_pending'
  end;

  if v_outcome <> 'reject' then
    if p_product_variant_id is null then
      raise exception 'Model HP wajib dipilih';
    end if;
    if nullif(trim(coalesce(p_product_label, '')), '') is null then
      raise exception 'Label produk wajib diisi';
    end if;
    if coalesce(p_tenor_months, 0) <= 0 then
      raise exception 'Tenor wajib diisi';
    end if;
  end if;

  insert into public.vast_applications (
    created_by_user_id,
    promotor_id,
    store_id,
    application_date,
    customer_name,
    customer_phone,
    pekerjaan,
    monthly_income,
    has_npwp,
    product_variant_id,
    product_label,
    limit_amount,
    dp_amount,
    tenor_months,
    outcome_status,
    lifecycle_status,
    notes
  ) values (
    v_user_id,
    v_user_id,
    v_store_id,
    coalesce(p_application_date, public.vast_current_date_wita()),
    trim(p_customer_name),
    trim(p_customer_phone),
    trim(p_pekerjaan),
    case when v_outcome = 'reject' then 0 else coalesce(p_monthly_income, 0) end,
    false,
    case when v_outcome = 'reject' then null else p_product_variant_id end,
    case when v_outcome = 'reject' then 'REJECT' else trim(coalesce(p_product_label, '')) end,
    case when v_outcome = 'reject' then 0 else coalesce(p_limit_amount, 0) end,
    case when v_outcome = 'reject' then 0 else coalesce(p_dp_amount, 0) end,
    case when v_outcome = 'reject' then 1 else p_tenor_months end,
    v_outcome,
    v_lifecycle,
    nullif(trim(coalesce(p_notes, '')), '')
  )
  returning id into v_application_id;

  return jsonb_build_object(
    'application_id', v_application_id,
    'outcome_status', v_outcome,
    'lifecycle_status', v_lifecycle
  );
end;
$$;

create or replace function public.attach_vast_application_evidence(
  p_application_id uuid,
  p_file_url text,
  p_file_name text default null,
  p_mime_type text default null,
  p_file_size_bytes bigint default null,
  p_sha256_hex text default null,
  p_perceptual_hash text default null,
  p_source_stage text default 'initial',
  p_evidence_type text default 'application_proof'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_evidence_id uuid;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if p_application_id is null or nullif(trim(coalesce(p_file_url, '')), '') is null then
    raise exception 'Lampiran bukti tidak valid';
  end if;

  if not exists (
    select 1
    from public.vast_applications va
    where va.id = p_application_id
      and va.promotor_id = v_user_id
  ) then
    raise exception 'Pengajuan VAST tidak ditemukan';
  end if;

  insert into public.vast_application_evidences (
    application_id,
    source_stage,
    evidence_type,
    file_url,
    file_name,
    mime_type,
    file_size_bytes,
    sha256_hex,
    perceptual_hash,
    created_by_user_id
  ) values (
    p_application_id,
    coalesce(nullif(trim(coalesce(p_source_stage, '')), ''), 'initial'),
    coalesce(nullif(trim(coalesce(p_evidence_type, '')), ''), 'application_proof'),
    trim(p_file_url),
    nullif(trim(coalesce(p_file_name, '')), ''),
    nullif(trim(coalesce(p_mime_type, '')), ''),
    p_file_size_bytes,
    nullif(trim(coalesce(p_sha256_hex, '')), ''),
    nullif(trim(coalesce(p_perceptual_hash, '')), ''),
    v_user_id
  )
  returning id into v_evidence_id;

  return jsonb_build_object(
    'evidence_id', v_evidence_id
  );
end;
$$;

create or replace function public.submit_promotion_report(
  p_platform text,
  p_post_url text default null,
  p_screenshot_urls text[] default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_store_id uuid;
  v_report_id uuid;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_platform, '')), '') is null then
    raise exception 'Platform wajib diisi';
  end if;

  if coalesce(array_length(p_screenshot_urls, 1), 0) = 0 then
    raise exception 'Minimal 1 screenshot wajib diupload';
  end if;

  select aps.store_id
    into v_store_id
  from public.assignments_promotor_store aps
  where aps.promotor_id = v_user_id
    and aps.active = true
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    raise exception 'Toko aktif promotor tidak ditemukan';
  end if;

  insert into public.promotion_reports (
    promotor_id,
    store_id,
    platform,
    post_url,
    screenshot_urls,
    notes,
    status,
    posted_at
  ) values (
    v_user_id,
    v_store_id,
    lower(trim(p_platform)),
    nullif(trim(coalesce(p_post_url, '')), ''),
    p_screenshot_urls,
    nullif(trim(coalesce(p_notes, '')), ''),
    'submitted',
    now()
  )
  returning id into v_report_id;

  return jsonb_build_object(
    'report_id', v_report_id
  );
end;
$$;

create or replace function public.submit_follower_report(
  p_platform text,
  p_username text,
  p_screenshot_url text default null,
  p_follower_count integer default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_store_id uuid;
  v_report_id uuid;
  v_username text;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  if nullif(trim(coalesce(p_platform, '')), '') is null then
    raise exception 'Platform wajib diisi';
  end if;

  v_username := trim(coalesce(p_username, ''));
  if v_username = '' then
    raise exception 'Username wajib diisi';
  end if;
  if left(v_username, 1) <> '@' then
    v_username := '@' || v_username;
  end if;

  select aps.store_id
    into v_store_id
  from public.assignments_promotor_store aps
  where aps.promotor_id = v_user_id
    and aps.active = true
  order by aps.created_at desc nulls last
  limit 1;

  if v_store_id is null then
    raise exception 'Toko aktif promotor tidak ditemukan';
  end if;

  insert into public.follower_reports (
    promotor_id,
    store_id,
    platform,
    username,
    screenshot_url,
    follower_count,
    notes,
    status,
    followed_at
  ) values (
    v_user_id,
    v_store_id,
    lower(trim(p_platform)),
    v_username,
    nullif(trim(coalesce(p_screenshot_url, '')), ''),
    p_follower_count,
    nullif(trim(coalesce(p_notes, '')), ''),
    'submitted',
    now()
  )
  returning id into v_report_id;

  return jsonb_build_object(
    'report_id', v_report_id
  );
end;
$$;

grant execute on function public.submit_promotor_stock_input(jsonb) to authenticated;
grant execute on function public.submit_promotor_stock_validation(date, uuid[]) to authenticated;
grant execute on function public.submit_promotor_vast_application(date, text, text, text, numeric, uuid, text, numeric, numeric, integer, text, text) to authenticated;
grant execute on function public.attach_vast_application_evidence(uuid, text, text, text, bigint, text, text, text, text) to authenticated;
grant execute on function public.submit_promotion_report(text, text, text[], text) to authenticated;
grant execute on function public.submit_follower_report(text, text, text, integer, text) to authenticated;
