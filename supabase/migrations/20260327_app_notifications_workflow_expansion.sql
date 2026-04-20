create or replace function public.handle_sell_out_void_request_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_promotor_name text := 'Promotor';
  v_store_name text := 'Toko';
  v_product_name text := 'Produk';
  v_title text;
  v_body text;
  v_route text;
  v_request_id uuid := coalesce(new.id, old.id);
  v_sale_id uuid := coalesce(new.sale_id, old.sale_id);
  v_promotor_id uuid := coalesce(new.promotor_id, old.promotor_id);
  v_actor_id uuid := coalesce(new.reviewed_by, new.requested_by, old.reviewed_by, old.requested_by);
  v_row record;
begin
  select
    coalesce(u.full_name, 'Promotor'),
    coalesce(st.store_name, 'Toko'),
    coalesce(p.model_name, 'Produk')
  into
    v_promotor_name,
    v_store_name,
    v_product_name
  from public.sales_sell_out so
  left join public.users u on u.id = so.promotor_id
  left join public.stores st on st.id = so.store_id
  left join public.product_variants pv on pv.id = so.variant_id
  left join public.products p on p.id = pv.product_id
  where so.id = v_sale_id;

  if tg_op = 'INSERT' and new.status = 'pending' then
    for v_row in
      select distinct hsp.sator_id
      from public.hierarchy_sator_promotor hsp
      where hsp.promotor_id = new.promotor_id
        and hsp.active = true
        and hsp.sator_id is not null
    loop
      perform public.create_app_notification(
        p_recipient_user_id := v_row.sator_id,
        p_actor_user_id := coalesce(new.requested_by, new.promotor_id),
        p_role_target := 'sator',
        p_category := 'approval',
        p_type := 'sell_out_void_requested',
        p_title := 'Pengajuan batal penjualan',
        p_body := format(
          '%s mengajukan batal penjualan %s di %s.',
          v_promotor_name,
          v_product_name,
          v_store_name
        ),
        p_entity_type := 'sell_out_void_request',
        p_entity_id := new.id,
        p_action_route := '/sator/notifications',
        p_action_params := jsonb_build_object(
          'request_id', new.id,
          'sale_id', new.sale_id,
          'promotor_id', new.promotor_id
        ),
        p_payload := jsonb_build_object(
          'request_id', new.id,
          'sale_id', new.sale_id,
          'store_name', v_store_name,
          'product_name', v_product_name,
          'reason', new.reason,
          'status', new.status
        ),
        p_priority := 'high',
        p_dedupe_key := format('void_request_pending:%s:%s', new.id, v_row.sator_id)
      );
    end loop;

    return new;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.status, '') = 'pending'
     and new.status in ('approved', 'rejected')
  then
    v_title := case
      when new.status = 'approved' then 'Pengajuan batal disetujui'
      else 'Pengajuan batal ditolak'
    end;
    v_body := case
      when new.status = 'approved' then format(
        'Pengajuan batal penjualan %s di %s sudah disetujui.',
        v_product_name,
        v_store_name
      )
      else format(
        'Pengajuan batal penjualan %s di %s ditolak.',
        v_product_name,
        v_store_name
      )
    end;
    v_route := '/promotor/aktivitas-harian';

    perform public.create_app_notification(
      p_recipient_user_id := v_promotor_id,
      p_actor_user_id := v_actor_id,
      p_role_target := 'promotor',
      p_category := 'approval',
      p_type := format('sell_out_void_%s', new.status),
      p_title := v_title,
      p_body := v_body,
      p_entity_type := 'sell_out_void_request',
      p_entity_id := v_request_id,
      p_action_route := v_route,
      p_action_params := jsonb_build_object(
        'request_id', v_request_id,
        'sale_id', v_sale_id
      ),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'sale_id', v_sale_id,
        'store_name', v_store_name,
        'product_name', v_product_name,
        'status', new.status,
        'review_note', new.review_note
      ),
      p_priority := 'high',
      p_dedupe_key := format('void_request_%s:%s', new.status, v_request_id)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trigger_sell_out_void_request_notifications on public.sell_out_void_requests;
create trigger trigger_sell_out_void_request_notifications
after insert or update of status on public.sell_out_void_requests
for each row
execute function public.handle_sell_out_void_request_notifications();

create or replace function public.handle_schedule_change_request_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_promotor_name text := 'Promotor';
  v_requested_date text := '';
  v_request_id uuid := coalesce(new.id, old.id);
  v_promotor_id uuid := coalesce(new.promotor_id, old.promotor_id);
  v_actor_id uuid := coalesce(new.sator_id, old.sator_id);
  v_row record;
begin
  select
    coalesce(u.full_name, 'Promotor'),
    to_char(coalesce(new.requested_date, old.requested_date), 'DD Mon YYYY')
  into
    v_promotor_name,
    v_requested_date
  from public.users u
  where u.id = v_promotor_id;

  if tg_op = 'INSERT' and new.status = 'pending' then
    for v_row in
      select distinct hsp.sator_id
      from public.hierarchy_sator_promotor hsp
      where hsp.promotor_id = new.promotor_id
        and hsp.active = true
        and hsp.sator_id is not null
    loop
      perform public.create_app_notification(
        p_recipient_user_id := v_row.sator_id,
        p_actor_user_id := new.promotor_id,
        p_role_target := 'sator',
        p_category := 'approval',
        p_type := 'schedule_change_requested',
        p_title := 'Pengajuan ubah jadwal',
        p_body := format(
          '%s mengajukan perubahan jadwal untuk %s.',
          v_promotor_name,
          v_requested_date
        ),
        p_entity_type := 'schedule_change_request',
        p_entity_id := new.id,
        p_action_route := '/sator/jadwal',
        p_action_params := jsonb_build_object(
          'request_id', new.id,
          'promotor_id', new.promotor_id,
          'requested_date', new.requested_date
        ),
        p_payload := jsonb_build_object(
          'request_id', new.id,
          'requested_date', new.requested_date,
          'original_shift_type', new.original_shift_type,
          'requested_shift_type', new.requested_shift_type,
          'reason', new.reason,
          'status', new.status
        ),
        p_priority := 'high',
        p_dedupe_key := format('schedule_change_pending:%s:%s', new.id, v_row.sator_id)
      );
    end loop;

    return new;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.status, '') = 'pending'
     and new.status in ('approved', 'rejected')
  then
    perform public.create_app_notification(
      p_recipient_user_id := v_promotor_id,
      p_actor_user_id := v_actor_id,
      p_role_target := 'promotor',
      p_category := 'approval',
      p_type := format('schedule_change_%s', new.status),
      p_title := case
        when new.status = 'approved' then 'Perubahan jadwal disetujui'
        else 'Perubahan jadwal ditolak'
      end,
      p_body := case
        when new.status = 'approved' then format(
          'Pengajuan perubahan jadwal untuk %s sudah disetujui.',
          v_requested_date
        )
        else format(
          'Pengajuan perubahan jadwal untuk %s ditolak.',
          v_requested_date
        )
      end,
      p_entity_type := 'schedule_change_request',
      p_entity_id := v_request_id,
      p_action_route := '/promotor/jadwal-bulanan',
      p_action_params := jsonb_build_object(
        'request_id', v_request_id,
        'requested_date', coalesce(new.requested_date, old.requested_date)
      ),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'requested_date', coalesce(new.requested_date, old.requested_date),
        'status', new.status,
        'sator_comment', new.sator_comment
      ),
      p_priority := 'high',
      p_dedupe_key := format('schedule_change_%s:%s', new.status, v_request_id)
    );
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.schedule_change_requests') is not null then
    execute 'drop trigger if exists trigger_schedule_change_request_notifications on public.schedule_change_requests';
    execute 'create trigger trigger_schedule_change_request_notifications after insert or update of status on public.schedule_change_requests for each row execute function public.handle_schedule_change_request_notifications()';
  end if;
end $$;
