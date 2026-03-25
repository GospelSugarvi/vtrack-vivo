update public.imei_normalizations
set status = case
  when status = 'pending' then 'reported'
  when status = 'sent' then 'processing'
  when status in ('normalized', 'normal') then 'ready_to_scan'
  else status
end
where status in ('pending', 'sent', 'normalized', 'normal');

alter table public.imei_normalizations
drop constraint if exists imei_normalizations_status_check;

alter table public.imei_normalizations
add constraint imei_normalizations_status_check
check (
  status in (
    'reported',
    'processing',
    'ready_to_scan',
    'scanned',
    'pending',
    'sent',
    'normalized',
    'normal'
  )
);

create or replace function public.send_imei_to_sator(p_normalization_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
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

  return json_build_object(
    'success', true,
    'message', 'IMEI marked as normalized'
  );
end;
$$;

create or replace function public.mark_imei_scanned(p_normalization_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.imei_normalizations
  set
    status = 'scanned',
    scanned_at = now(),
    updated_at = now()
  where id = p_normalization_id
    and status in ('ready_to_scan', 'normalized', 'normal');

  if not found then
    return json_build_object(
      'success', false,
      'error', 'IMEI normalization record not found or not ready to scan'
    );
  end if;

  return json_build_object(
    'success', true,
    'message', 'IMEI marked as scanned'
  );
end;
$$;

create or replace function public.get_imei_normalization_summary(p_promotor_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  return (
    select json_build_object(
      'total_imei', count(*),
      'reported_count', count(*) filter (where status = 'reported'),
      'processing_count', count(*) filter (where status = 'processing'),
      'ready_to_scan_count', count(*) filter (where status = 'ready_to_scan'),
      'scanned_count', count(*) filter (where status = 'scanned'),
      'needs_action', count(*) filter (where status in ('reported', 'processing', 'ready_to_scan')) > 0
    )
    from public.imei_normalizations
    where promotor_id = p_promotor_id
  );
end;
$$;

create or replace function public.get_sator_imei_list(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  result json;
begin
  with visible_rows as (
    select distinct i.*
    from public.imei_normalizations i
    where exists (
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = p_sator_id
        and hsp.promotor_id = i.promotor_id
        and hsp.active = true
    )
    or exists (
      select 1
      from public.sator_store_assignments ssa
      where ssa.sator_id = p_sator_id
        and ssa.store_id = i.store_id
        and ssa.is_active = true
    )
  )
  select coalesce(
    json_agg(
      json_build_object(
        'id', i.id,
        'imei', i.imei,
        'product_name', coalesce(p.model_name || ' ' || pv.ram_rom || ' ' || pv.color, 'Unknown Product'),
        'status', case
          when i.status = 'sent' then 'processing'
          when i.status in ('normalized', 'normal') then 'ready_to_scan'
          when i.status = 'pending' then 'reported'
          else i.status
        end,
        'promotor_name', coalesce(u.full_name, 'Unknown Promotor'),
        'store_name', coalesce(s.store_name, 'Unknown Store'),
        'sold_at', i.sold_at,
        'sent_to_sator_at', i.sent_to_sator_at,
        'normalized_at', i.normalized_at,
        'scanned_at', i.scanned_at,
        'notes', i.notes,
        'created_at', i.created_at,
        'updated_at', i.updated_at
      )
      order by i.created_at desc
    ),
    '[]'::json
  )
  into result
  from visible_rows i
  left join public.users u on i.promotor_id = u.id
  left join public.stores s on i.store_id = s.id
  left join public.product_variants pv on i.variant_id = pv.id
  left join public.products p on i.product_id = p.id;

  return result;
end;
$$;

grant execute on function public.send_imei_to_sator(uuid) to authenticated;
grant execute on function public.mark_imei_normalized(uuid, uuid, text) to authenticated;
grant execute on function public.mark_imei_scanned(uuid) to authenticated;
grant execute on function public.get_imei_normalization_summary(uuid) to authenticated;
grant execute on function public.get_sator_imei_list(uuid) to authenticated;
