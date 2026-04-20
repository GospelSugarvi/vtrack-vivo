create or replace function public.commit_warehouse_import(
  p_file_name text,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_run_id uuid;
  v_row jsonb;
  v_store_id uuid;
  v_group_id uuid;
  v_variant_id uuid;
  v_product_id uuid;
  v_stok_id uuid;
  v_preview_status text;
  v_final_status text;
  v_target_type text;
  v_imei text;
  v_note text;
  v_total_rows integer := 0;
  v_ready_rows integer := 0;
  v_inserted_store_rows integer := 0;
  v_staged_group_rows integer := 0;
  v_skipped_rows integer := 0;
  v_issue_rows integer := 0;
  v_duplicate_imei_rows integer := 0;
begin
  if not public.is_admin_user() then
    raise exception 'Only admin can commit warehouse import';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows must be a JSON array';
  end if;

  insert into public.warehouse_import_runs (
    file_name,
    created_by
  ) values (
    coalesce(nullif(trim(p_file_name), ''), 'warehouse_import.xlsx'),
    v_actor_id
  )
  returning id into v_run_id;

  for v_row in
    select value
    from jsonb_array_elements(p_rows)
  loop
    v_total_rows := v_total_rows + 1;
    v_preview_status := coalesce(v_row->>'preview_status', 'unknown');
    v_target_type := nullif(v_row->>'target_type', '');
    v_store_id := nullif(v_row->>'store_id', '')::uuid;
    v_group_id := nullif(v_row->>'group_id', '')::uuid;
    v_variant_id := nullif(v_row->>'variant_id', '')::uuid;
    v_product_id := nullif(v_row->>'product_id', '')::uuid;
    v_imei := regexp_replace(coalesce(v_row->>'imei', ''), '\s+', '', 'g');
    v_imei := nullif(trim(v_imei), '');
    v_stok_id := null;
    v_note := null;
    v_final_status := v_preview_status;

    if v_preview_status = 'ready' then
      v_ready_rows := v_ready_rows + 1;

      if v_target_type = 'singleStore' then
        if v_store_id is null or v_variant_id is null or v_product_id is null then
          v_final_status := 'missing_target_payload';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Store/variant/product payload tidak lengkap';
        elsif not exists (
          select 1
          from public.stores st
          where st.id = v_store_id
            and st.deleted_at is null
        ) then
          v_final_status := 'store_not_found';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Store target tidak ditemukan';
        elsif not exists (
          select 1
          from public.product_variants pv
          where pv.id = v_variant_id
            and pv.product_id = v_product_id
            and coalesce(pv.active, true) = true
            and pv.deleted_at is null
        ) then
          v_final_status := 'variant_payload_mismatch';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Variant/product payload tidak cocok dengan master';
        elsif v_imei is null or length(v_imei) <> 15 or v_imei !~ '^[0-9]{15}$' then
          v_final_status := 'invalid_imei';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'IMEI tidak valid';
        elsif exists (
          select 1 from public.stok s where s.imei = v_imei
        ) then
          v_final_status := 'duplicate_imei';
          v_duplicate_imei_rows := v_duplicate_imei_rows + 1;
          v_note := 'IMEI sudah ada di stok';
        else
          insert into public.stok (
            product_id,
            variant_id,
            store_id,
            imei,
            tipe_stok,
            created_by
          ) values (
            v_product_id,
            v_variant_id,
            v_store_id,
            v_imei,
            'fresh',
            v_actor_id
          )
          returning id into v_stok_id;

          insert into public.stock_movement_log (
            stok_id,
            imei,
            to_store_id,
            movement_type,
            moved_by,
            note
          ) values (
            v_stok_id,
            v_imei,
            v_store_id,
            'initial',
            v_actor_id,
            format('Warehouse import run %s', v_run_id)
          );

          v_final_status := 'inserted_store';
          v_inserted_store_rows := v_inserted_store_rows + 1;
        end if;
      elsif v_target_type in ('sharedGroup', 'distributedGroup') then
        if v_group_id is null then
          v_final_status := 'missing_group_payload';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Group payload tidak lengkap';
        elsif not exists (
          select 1
          from public.store_groups sg
          where sg.id = v_group_id
            and sg.deleted_at is null
        ) then
          v_final_status := 'group_not_found';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Group target tidak ditemukan';
        elsif v_variant_id is null or v_product_id is null then
          v_final_status := 'missing_variant_payload';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Variant/product payload grup tidak lengkap';
        elsif not exists (
          select 1
          from public.product_variants pv
          where pv.id = v_variant_id
            and pv.product_id = v_product_id
            and coalesce(pv.active, true) = true
            and pv.deleted_at is null
        ) then
          v_final_status := 'variant_payload_mismatch';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'Variant/product payload tidak cocok dengan master';
        elsif v_imei is null or length(v_imei) <> 15 or v_imei !~ '^[0-9]{15}$' then
          v_final_status := 'invalid_imei';
          v_issue_rows := v_issue_rows + 1;
          v_note := 'IMEI tidak valid';
        elsif exists (
          select 1 from public.stok s where s.imei = v_imei
        ) then
          v_final_status := 'duplicate_imei';
          v_duplicate_imei_rows := v_duplicate_imei_rows + 1;
          v_note := 'IMEI sudah ada di stok';
        else
          v_final_status := case
            when v_target_type = 'sharedGroup' then 'staged_shared_group'
            else 'staged_distributed_group'
          end;
          v_staged_group_rows := v_staged_group_rows + 1;
          v_note := 'Belum diinsert ke stok toko; menunggu alur grup';
        end if;
      else
        v_final_status := 'unknown_target_type';
        v_issue_rows := v_issue_rows + 1;
        v_note := 'Target type tidak dikenali';
      end if;
    elsif v_preview_status = 'skipped_spc' then
      v_skipped_rows := v_skipped_rows + 1;
    else
      v_issue_rows := v_issue_rows + 1;
    end if;

    insert into public.warehouse_import_run_items (
      run_id,
      row_number,
      warehouse_name,
      product_name,
      imei,
      preview_status,
      final_status,
      target_type,
      store_id,
      group_id,
      variant_id,
      product_id,
      stok_id,
      note
    ) values (
      v_run_id,
      coalesce((v_row->>'row_number')::integer, 0),
      coalesce(v_row->>'warehouse_name', ''),
      coalesce(v_row->>'product_name', ''),
      v_imei,
      v_preview_status,
      v_final_status,
      v_target_type,
      v_store_id,
      v_group_id,
      v_variant_id,
      v_product_id,
      v_stok_id,
      coalesce(v_note, array_to_string(array(
        select jsonb_array_elements_text(coalesce(v_row->'notes', '[]'::jsonb))
      ), ' • '))
    );
  end loop;

  update public.warehouse_import_runs
  set total_rows = v_total_rows,
      ready_rows = v_ready_rows,
      inserted_store_rows = v_inserted_store_rows,
      staged_group_rows = v_staged_group_rows,
      skipped_rows = v_skipped_rows,
      issue_rows = v_issue_rows,
      duplicate_imei_rows = v_duplicate_imei_rows
  where id = v_run_id;

  return jsonb_build_object(
    'run_id', v_run_id,
    'total_rows', v_total_rows,
    'ready_rows', v_ready_rows,
    'inserted_store_rows', v_inserted_store_rows,
    'staged_group_rows', v_staged_group_rows,
    'skipped_rows', v_skipped_rows,
    'issue_rows', v_issue_rows,
    'duplicate_imei_rows', v_duplicate_imei_rows
  );
end;
$$;

grant execute on function public.commit_warehouse_import(text, jsonb) to authenticated;
