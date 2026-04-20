create or replace function public.create_app_notification(
  p_recipient_user_id uuid,
  p_actor_user_id uuid,
  p_role_target text,
  p_category text,
  p_type text,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id text default null,
  p_action_route text default null,
  p_action_params jsonb default '{}'::jsonb,
  p_payload jsonb default '{}'::jsonb,
  p_priority text default 'normal',
  p_dedupe_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_notification_id uuid;
  v_category text := lower(coalesce(trim(p_category), 'system'));
  v_pref record;
  v_allowed boolean := true;
begin
  if p_recipient_user_id is null then
    return null;
  end if;

  select
    coalesce(np.inbox_enabled, true) as inbox_enabled,
    coalesce(np.approval_enabled, true) as approval_enabled,
    coalesce(np.stock_enabled, true) as stock_enabled,
    coalesce(np.sales_enabled, true) as sales_enabled,
    coalesce(np.schedule_enabled, true) as schedule_enabled,
    coalesce(np.system_enabled, true) as system_enabled
  into v_pref
  from public.notification_preferences np
  where np.user_id = p_recipient_user_id;

  if not found then
    v_pref.inbox_enabled := true;
    v_pref.approval_enabled := true;
    v_pref.stock_enabled := true;
    v_pref.sales_enabled := true;
    v_pref.schedule_enabled := true;
    v_pref.system_enabled := true;
  end if;

  if not coalesce(v_pref.inbox_enabled, true) then
    return null;
  end if;

  v_allowed := case v_category
    when 'approval' then coalesce(v_pref.approval_enabled, true)
    when 'stock' then coalesce(v_pref.stock_enabled, true)
    when 'sales' then coalesce(v_pref.sales_enabled, true)
    when 'schedule' then coalesce(v_pref.schedule_enabled, true)
    when 'system' then coalesce(v_pref.system_enabled, true)
    else true
  end;

  if not v_allowed then
    return null;
  end if;

  insert into public.app_notifications (
    recipient_user_id,
    actor_user_id,
    role_target,
    category,
    type,
    title,
    body,
    entity_type,
    entity_id,
    action_route,
    action_params,
    payload,
    priority,
    dedupe_key
  )
  values (
    p_recipient_user_id,
    p_actor_user_id,
    p_role_target,
    p_category,
    p_type,
    p_title,
    p_body,
    p_entity_type,
    p_entity_id,
    p_action_route,
    coalesce(p_action_params, '{}'::jsonb),
    coalesce(p_payload, '{}'::jsonb),
    coalesce(nullif(trim(p_priority), ''), 'normal'),
    nullif(trim(coalesce(p_dedupe_key, '')), '')
  )
  on conflict (dedupe_key) do update
  set
    actor_user_id = excluded.actor_user_id,
    title = excluded.title,
    body = excluded.body,
    action_route = excluded.action_route,
    action_params = excluded.action_params,
    payload = excluded.payload,
    priority = excluded.priority,
    status = 'unread',
    read_at = null,
    archived_at = null
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;
