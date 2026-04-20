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
  returning i.id into v_deleted_id;

  if v_deleted_id is null then
    raise exception 'Item IMEI tidak ditemukan atau bukan milik Anda';
  end if;

  return jsonb_build_object(
    'success', true,
    'normalization_id', v_deleted_id
  );
end;
$$;

grant execute on function public.delete_promotor_imei_normalization_draft(uuid) to authenticated;
