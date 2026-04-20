alter table public.feed_comments
  add column if not exists parent_comment_id uuid references public.feed_comments(id) on delete cascade,
  add column if not exists mentioned_user_ids uuid[] not null default '{}'::uuid[],
  add column if not exists metadata_json jsonb not null default '{}'::jsonb;

create index if not exists idx_feed_comments_parent
  on public.feed_comments(parent_comment_id)
  where parent_comment_id is not null;

create index if not exists idx_feed_comments_mentions
  on public.feed_comments using gin (mentioned_user_ids);

create table if not exists public.ai_feed_comment_reply_jobs (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales_sell_out(id) on delete cascade,
  source_comment_id uuid not null unique references public.feed_comments(id) on delete cascade,
  persona_user_id uuid references public.users(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'skipped')),
  attempt_count integer not null default 0,
  generated_comment text,
  reply_comment_id uuid references public.feed_comments(id) on delete set null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists idx_ai_feed_comment_reply_jobs_status_created
  on public.ai_feed_comment_reply_jobs(status, created_at);

create or replace function public.update_ai_feed_comment_reply_jobs_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_ai_feed_comment_reply_jobs_updated_at on public.ai_feed_comment_reply_jobs;
create trigger trg_ai_feed_comment_reply_jobs_updated_at
before update on public.ai_feed_comment_reply_jobs
for each row
execute function public.update_ai_feed_comment_reply_jobs_updated_at();

alter table public.ai_feed_comment_reply_jobs enable row level security;

drop policy if exists "ai_feed_comment_reply_jobs_read_admin" on public.ai_feed_comment_reply_jobs;
create policy "ai_feed_comment_reply_jobs_read_admin"
on public.ai_feed_comment_reply_jobs
for select
to authenticated
using (public.is_admin_user());

drop policy if exists "ai_feed_comment_reply_jobs_manage_admin" on public.ai_feed_comment_reply_jobs;
create policy "ai_feed_comment_reply_jobs_manage_admin"
on public.ai_feed_comment_reply_jobs
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

create or replace function public.get_sale_comments(
    p_sale_id uuid,
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    comment_id uuid,
    user_id uuid,
    user_name text,
    user_avatar text,
    user_role text,
    comment_text text,
    created_at timestamptz,
    parent_comment_id uuid,
    mentioned_user_ids uuid[],
    is_system_persona boolean
) as $$
begin
    return query
    select
        fc.id as comment_id,
        u.id as user_id,
        coalesce(sp.display_name, u.full_name) as user_name,
        u.avatar_url as user_avatar,
        u.role::text as user_role,
        fc.comment_text,
        fc.created_at,
        fc.parent_comment_id,
        coalesce(fc.mentioned_user_ids, '{}'::uuid[]) as mentioned_user_ids,
        (sp.id is not null) as is_system_persona
    from public.feed_comments fc
    join public.users u on u.id = fc.user_id
    left join public.system_personas sp
      on sp.linked_user_id = u.id
     and sp.is_active = true
    where fc.sale_id = p_sale_id
      and fc.deleted_at is null
    order by fc.created_at asc
    limit p_limit
    offset p_offset;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.add_comment(
    p_sale_id uuid,
    p_user_id uuid,
    p_comment_text text,
    p_parent_comment_id uuid default null,
    p_mentioned_user_ids uuid[] default null
)
returns uuid as $$
declare
    v_comment_id uuid;
    v_parent_sale_id uuid;
begin
    if trim(coalesce(p_comment_text, '')) = '' then
      raise exception 'Comment text is required.';
    end if;

    if p_parent_comment_id is not null then
      select fc.sale_id
        into v_parent_sale_id
      from public.feed_comments fc
      where fc.id = p_parent_comment_id
        and fc.deleted_at is null
      limit 1;

      if v_parent_sale_id is null then
        raise exception 'Parent comment not found.';
      end if;

      if v_parent_sale_id <> p_sale_id then
        raise exception 'Parent comment does not belong to this sale.';
      end if;
    end if;

    insert into public.feed_comments (
      sale_id,
      user_id,
      comment_text,
      parent_comment_id,
      mentioned_user_ids
    )
    values (
      p_sale_id,
      p_user_id,
      trim(p_comment_text),
      p_parent_comment_id,
      coalesce(p_mentioned_user_ids, '{}'::uuid[])
    )
    returning id into v_comment_id;

    return v_comment_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function public.enqueue_live_feed_ai_comment_reply_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean := false;
  v_system_persona_id uuid;
  v_persona_user_id uuid;
  v_parent_user_id uuid;
  v_should_enqueue boolean := false;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  select afs.enabled,
         nullif(afs.config_json->>'system_persona_id', '')::uuid,
         nullif(afs.config_json->>'persona_user_id', '')::uuid
    into v_enabled, v_system_persona_id, v_persona_user_id
  from public.ai_feature_settings afs
  where afs.feature_key = 'live_feed_sales_comment'
  limit 1;

  if coalesce(v_enabled, false) = false then
    return new;
  end if;

  if v_system_persona_id is not null then
    select sp.linked_user_id
      into v_persona_user_id
    from public.system_personas sp
    where sp.id = v_system_persona_id
      and sp.is_active = true
    limit 1;
  end if;

  if v_persona_user_id is null then
    return new;
  end if;

  if new.user_id = v_persona_user_id then
    return new;
  end if;

  if v_persona_user_id = any(coalesce(new.mentioned_user_ids, '{}'::uuid[])) then
    v_should_enqueue := true;
  end if;

  if new.parent_comment_id is not null then
    select fc.user_id
      into v_parent_user_id
    from public.feed_comments fc
    where fc.id = new.parent_comment_id
      and fc.deleted_at is null
    limit 1;

    if v_parent_user_id = v_persona_user_id then
      v_should_enqueue := true;
    end if;
  end if;

  if v_should_enqueue then
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
    on conflict (source_comment_id) do nothing;

    perform public.dispatch_live_feed_ai_sales_comment_worker(1);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enqueue_live_feed_ai_comment_reply_job on public.feed_comments;
create trigger trg_enqueue_live_feed_ai_comment_reply_job
after insert on public.feed_comments
for each row
execute function public.enqueue_live_feed_ai_comment_reply_job();

comment on table public.ai_feed_comment_reply_jobs is
  'Queue for persona replies to user comments in live feed threads.';
