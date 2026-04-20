create extension if not exists pg_net;

create or replace function public.dispatch_live_feed_ai_sales_comment_worker(
  p_batch_size integer default 1
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id bigint;
begin
  v_request_id := net.http_post(
    url := 'https://ytslgrlieofvvfstwqfk.supabase.co/functions/v1/process-live-feed-ai-comments',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_SKD59vkOUkVyceDmKLYZ7g_CDr9b0wi'
    ),
    body := jsonb_build_object(
      'batch_size',
      greatest(1, least(coalesce(p_batch_size, 1), 20))
    ),
    timeout_milliseconds := 10000
  );

  return v_request_id;
end;
$$;

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
    perform public.dispatch_live_feed_ai_sales_comment_worker(1);
  end if;

  return new;
end;
$$;
