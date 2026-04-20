create or replace function public.create_app_notification(
  p_recipient_user_id uuid,
  p_actor_user_id uuid,
  p_role_target text,
  p_category text,
  p_type text,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid,
  p_action_route text default null,
  p_action_params jsonb default '{}'::jsonb,
  p_payload jsonb default '{}'::jsonb,
  p_priority text default 'normal',
  p_dedupe_key text default null
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.create_app_notification(
    p_recipient_user_id := p_recipient_user_id,
    p_actor_user_id := p_actor_user_id,
    p_role_target := p_role_target,
    p_category := p_category,
    p_type := p_type,
    p_title := p_title,
    p_body := p_body,
    p_entity_type := p_entity_type,
    p_entity_id := p_entity_id::text,
    p_action_route := p_action_route,
    p_action_params := p_action_params,
    p_payload := p_payload,
    p_priority := p_priority,
    p_dedupe_key := p_dedupe_key
  );
$$;

grant execute on function public.create_app_notification(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  jsonb,
  jsonb,
  text,
  text
) to authenticated;
