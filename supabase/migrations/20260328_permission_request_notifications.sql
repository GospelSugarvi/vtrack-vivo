create or replace function public.handle_permission_request_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid := coalesce(new.id, old.id);
  v_promotor_id uuid := coalesce(new.promotor_id, old.promotor_id);
  v_sator_id uuid := coalesce(new.sator_id, old.sator_id);
  v_spv_id uuid := coalesce(new.spv_id, old.spv_id);
  v_promotor_name text := 'Promotor';
  v_request_date text := '';
  v_request_type text := 'izin';
begin
  select
    coalesce(u.full_name, 'Promotor'),
    to_char(coalesce(new.request_date, old.request_date), 'DD Mon YYYY')
  into
    v_promotor_name,
    v_request_date
  from public.users u
  where u.id = v_promotor_id;

  v_request_type := case coalesce(new.request_type, old.request_type)
    when 'sick' then 'izin sakit'
    when 'personal' then 'izin pribadi'
    when 'other' then 'izin lainnya'
    else 'izin'
  end;

  if tg_op = 'INSERT' and new.status = 'pending_sator' then
    perform public.create_app_notification(
      p_recipient_user_id := v_sator_id,
      p_actor_user_id := v_promotor_id,
      p_role_target := 'sator',
      p_category := 'approval',
      p_type := 'permission_request_submitted',
      p_title := 'Pengajuan perijinan baru',
      p_body := format(
        '%s mengajukan %s untuk %s.',
        v_promotor_name,
        v_request_type,
        v_request_date
      ),
      p_entity_type := 'permission_request',
      p_entity_id := v_request_id::text,
      p_action_route := '/sator/permission-approval',
      p_action_params := jsonb_build_object(
        'request_id', v_request_id,
        'promotor_id', v_promotor_id
      ),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'request_date', new.request_date,
        'request_type', new.request_type,
        'reason', new.reason,
        'status', new.status
      ),
      p_priority := 'high',
      p_dedupe_key := format(
        'permission_request_pending_sator:%s:%s',
        v_request_id,
        coalesce(v_sator_id::text, '')
      )
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.status, '') = 'pending_sator'
     and new.status = 'approved_sator'
  then
    perform public.create_app_notification(
      p_recipient_user_id := v_spv_id,
      p_actor_user_id := coalesce(new.sator_approved_by, v_sator_id),
      p_role_target := 'spv',
      p_category := 'approval',
      p_type := 'permission_request_waiting_spv',
      p_title := 'Approval perijinan menunggu SPV',
      p_body := format(
        '%s sudah disetujui SATOR dan menunggu keputusan SPV untuk %s.',
        v_request_type,
        v_request_date
      ),
      p_entity_type := 'permission_request',
      p_entity_id := v_request_id::text,
      p_action_route := '/spv/permission-approval',
      p_action_params := jsonb_build_object(
        'request_id', v_request_id,
        'promotor_id', v_promotor_id
      ),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'request_date', new.request_date,
        'request_type', new.request_type,
        'reason', new.reason,
        'status', new.status,
        'sator_comment', new.sator_comment
      ),
      p_priority := 'high',
      p_dedupe_key := format(
        'permission_request_pending_spv:%s:%s',
        v_request_id,
        coalesce(v_spv_id::text, '')
      )
    );

    perform public.create_app_notification(
      p_recipient_user_id := v_promotor_id,
      p_actor_user_id := coalesce(new.sator_approved_by, v_sator_id),
      p_role_target := 'promotor',
      p_category := 'approval',
      p_type := 'permission_request_approved_sator',
      p_title := 'Perijinan disetujui SATOR',
      p_body := format(
        'Pengajuan %s untuk %s sudah disetujui SATOR dan diteruskan ke SPV.',
        v_request_type,
        v_request_date
      ),
      p_entity_type := 'permission_request',
      p_entity_id := v_request_id::text,
      p_action_route := '/promotor/clock-in',
      p_action_params := jsonb_build_object('request_id', v_request_id),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'request_date', new.request_date,
        'request_type', new.request_type,
        'status', new.status,
        'sator_comment', new.sator_comment
      ),
      p_priority := 'high',
      p_dedupe_key := format('permission_request_approved_sator:%s', v_request_id)
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.status, '') = 'pending_sator'
     and new.status = 'rejected_sator'
  then
    perform public.create_app_notification(
      p_recipient_user_id := v_promotor_id,
      p_actor_user_id := coalesce(new.sator_approved_by, v_sator_id),
      p_role_target := 'promotor',
      p_category := 'approval',
      p_type := 'permission_request_rejected_sator',
      p_title := 'Perijinan ditolak SATOR',
      p_body := format(
        'Pengajuan %s untuk %s ditolak oleh SATOR.',
        v_request_type,
        v_request_date
      ),
      p_entity_type := 'permission_request',
      p_entity_id := v_request_id::text,
      p_action_route := '/promotor/clock-in',
      p_action_params := jsonb_build_object('request_id', v_request_id),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'request_date', new.request_date,
        'request_type', new.request_type,
        'status', new.status,
        'sator_comment', new.sator_comment
      ),
      p_priority := 'high',
      p_dedupe_key := format('permission_request_rejected_sator:%s', v_request_id)
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.status, '') = 'approved_sator'
     and new.status in ('approved_spv', 'rejected_spv')
  then
    perform public.create_app_notification(
      p_recipient_user_id := v_promotor_id,
      p_actor_user_id := coalesce(new.spv_approved_by, v_spv_id),
      p_role_target := 'promotor',
      p_category := 'approval',
      p_type := case
        when new.status = 'approved_spv' then 'permission_request_approved_spv'
        else 'permission_request_rejected_spv'
      end,
      p_title := case
        when new.status = 'approved_spv' then 'Perijinan disetujui SPV'
        else 'Perijinan ditolak SPV'
      end,
      p_body := case
        when new.status = 'approved_spv' then format(
          'Pengajuan %s untuk %s sudah disetujui SPV.',
          v_request_type,
          v_request_date
        )
        else format(
          'Pengajuan %s untuk %s ditolak oleh SPV.',
          v_request_type,
          v_request_date
        )
      end,
      p_entity_type := 'permission_request',
      p_entity_id := v_request_id::text,
      p_action_route := '/promotor/clock-in',
      p_action_params := jsonb_build_object('request_id', v_request_id),
      p_payload := jsonb_build_object(
        'request_id', v_request_id,
        'request_date', new.request_date,
        'request_type', new.request_type,
        'status', new.status,
        'spv_comment', new.spv_comment
      ),
      p_priority := 'high',
      p_dedupe_key := format('permission_request_final:%s:%s', new.status, v_request_id)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trigger_permission_request_notifications on public.permission_requests;
create trigger trigger_permission_request_notifications
after insert or update of status on public.permission_requests
for each row
execute function public.handle_permission_request_notifications();
