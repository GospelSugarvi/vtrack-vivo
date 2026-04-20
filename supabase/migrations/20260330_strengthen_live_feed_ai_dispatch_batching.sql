create or replace function public.enqueue_live_feed_ai_sales_comment_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean := false;
  v_job_id uuid;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if coalesce(new.is_chip_sale, false) then
    return new;
  end if;

  select afs.enabled
    into v_enabled
  from public.ai_feature_settings afs
  where afs.feature_key = 'live_feed_sales_comment'
  limit 1;

  if coalesce(v_enabled, false) = false then
    return new;
  end if;

  insert into public.ai_sales_comment_jobs (
    sale_id,
    feature_key,
    input_context_json
  )
  values (
    new.id,
    'live_feed_sales_comment',
    jsonb_build_object(
      'sale_id', new.id,
      'promotor_id', new.promotor_id,
      'store_id', new.store_id,
      'created_at', new.created_at
    )
  )
  on conflict (sale_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    perform public.dispatch_live_feed_ai_sales_comment_worker(5);
  end if;

  return new;
end;
$$;

create or replace function public.enqueue_live_feed_ai_comment_reply_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona_user_id uuid;
  v_target_persona_user_id uuid;
  v_target_user_id uuid;
  v_mentioned_user_ids uuid[] := '{}';
  v_job_id uuid;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  select sp.linked_user_id
    into v_persona_user_id
  from public.ai_feature_settings afs
  join public.system_personas sp
    on sp.id::text = coalesce(afs.config_json ->> 'system_persona_id', '')
   and sp.is_active = true
  where afs.feature_key = 'live_feed_sales_comment'
    and afs.enabled = true
  limit 1;

  if v_persona_user_id is null then
    return new;
  end if;

  if new.user_id = v_persona_user_id then
    return new;
  end if;

  if new.parent_comment_id is not null then
    select fc.user_id
      into v_target_user_id
    from public.feed_comments fc
    where fc.id = new.parent_comment_id;
  end if;

  v_target_persona_user_id := case
    when v_target_user_id = v_persona_user_id then v_persona_user_id
    when v_persona_user_id = any(coalesce(new.mentioned_user_ids, '{}')) then v_persona_user_id
    else null
  end;

  if v_target_persona_user_id is null then
    return new;
  end if;

  v_mentioned_user_ids := array(
    select distinct x
    from unnest(coalesce(new.mentioned_user_ids, '{}')) as x
    where x is not null
  );

  insert into public.ai_feed_comment_reply_jobs (
    sale_id,
    source_comment_id,
    persona_user_id
  )
  values (
    new.sale_id,
    new.id,
    v_persona_user_id
  )
  on conflict (source_comment_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    perform public.dispatch_live_feed_ai_sales_comment_worker(5);
  end if;

  return new;
end;
$$;
