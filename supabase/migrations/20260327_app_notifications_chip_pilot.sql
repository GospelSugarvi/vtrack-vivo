create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references public.users(id) on delete cascade,
  actor_user_id uuid null references public.users(id) on delete set null,
  role_target text not null,
  category text not null,
  type text not null,
  title text not null,
  body text not null,
  entity_type text not null,
  entity_id text null,
  action_route text null,
  action_params jsonb not null default '{}'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  priority text not null default 'normal'
    check (priority in ('low', 'normal', 'high')),
  status text not null default 'unread'
    check (status in ('unread', 'read', 'archived')),
  dedupe_key text unique,
  created_at timestamptz not null default now(),
  read_at timestamptz null,
  archived_at timestamptz null
);

create index if not exists idx_app_notifications_recipient_created
on public.app_notifications (recipient_user_id, created_at desc);

create index if not exists idx_app_notifications_recipient_status
on public.app_notifications (recipient_user_id, status, created_at desc);

alter table public.app_notifications enable row level security;

drop policy if exists "Users can read own notifications" on public.app_notifications;
create policy "Users can read own notifications"
on public.app_notifications
for select
using (recipient_user_id = auth.uid());

drop policy if exists "Users can update own notifications" on public.app_notifications;
create policy "Users can update own notifications"
on public.app_notifications
for update
using (recipient_user_id = auth.uid())
with check (recipient_user_id = auth.uid());

create table if not exists public.user_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  platform text not null,
  fcm_token text not null unique,
  device_label text null,
  app_version text null,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_device_tokens_user
on public.user_device_tokens (user_id, is_active);

alter table public.user_device_tokens enable row level security;

drop policy if exists "Users can read own device tokens" on public.user_device_tokens;
create policy "Users can read own device tokens"
on public.user_device_tokens
for select
using (user_id = auth.uid());

drop policy if exists "Users can insert own device tokens" on public.user_device_tokens;
create policy "Users can insert own device tokens"
on public.user_device_tokens
for insert
with check (user_id = auth.uid());

drop policy if exists "Users can update own device tokens" on public.user_device_tokens;
create policy "Users can update own device tokens"
on public.user_device_tokens
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "Users can delete own device tokens" on public.user_device_tokens;
create policy "Users can delete own device tokens"
on public.user_device_tokens
for delete
using (user_id = auth.uid());

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.users(id) on delete cascade,
  push_enabled boolean not null default true,
  inbox_enabled boolean not null default true,
  approval_enabled boolean not null default true,
  stock_enabled boolean not null default true,
  sales_enabled boolean not null default true,
  schedule_enabled boolean not null default true,
  system_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "Users can read own notification preferences" on public.notification_preferences;
create policy "Users can read own notification preferences"
on public.notification_preferences
for select
using (user_id = auth.uid());

drop policy if exists "Users can insert own notification preferences" on public.notification_preferences;
create policy "Users can insert own notification preferences"
on public.notification_preferences
for insert
with check (user_id = auth.uid());

drop policy if exists "Users can update own notification preferences" on public.notification_preferences;
create policy "Users can update own notification preferences"
on public.notification_preferences
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

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
begin
  if p_recipient_user_id is null then
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

create or replace function public.handle_chip_request_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_name text := 'Toko';
  v_promotor_name text := 'Promotor';
  v_actor_name text := 'SATOR';
  v_imei text := '-';
  v_request_label text := 'request chip';
  v_title text;
  v_body text;
begin
  select coalesce(s.store_name, 'Toko')
  into v_store_name
  from public.stores s
  where s.id = new.store_id;

  select coalesce(u.full_name, 'Promotor')
  into v_promotor_name
  from public.users u
  where u.id = new.promotor_id;

  select coalesce(s.imei, '-')
  into v_imei
  from public.stok s
  where s.id = new.stok_id;

  v_request_label := case
    when new.request_type = 'sold_to_chip' then 'ubah barang terjual jadi chip'
    else 'ubah stok jadi chip'
  end;

  if tg_op = 'INSERT' and new.status = 'pending' then
    v_title := 'Request chip baru';
    v_body := v_promotor_name || ' mengajukan ' || v_request_label ||
      ' untuk IMEI ' || v_imei || ' di ' || v_store_name;

    perform public.create_app_notification(
      new.sator_id,
      new.promotor_id,
      'sator',
      'approval',
      'chip_request_submitted',
      v_title,
      v_body,
      'stock_chip_request',
      new.id::text,
      '/sator/chip-approval',
      jsonb_build_object('request_id', new.id),
      jsonb_build_object(
        'request_type', new.request_type,
        'store_id', new.store_id,
        'stok_id', new.stok_id,
        'imei', v_imei
      ),
      'high',
      'chip_request_submitted:' || new.id::text || ':' || coalesce(new.sator_id::text, '')
    );

    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status is distinct from new.status
     and new.status in ('approved', 'rejected') then
    select coalesce(u.full_name, 'SATOR')
    into v_actor_name
    from public.users u
    where u.id = coalesce(new.approved_by, new.sator_id);

    if new.status = 'approved' then
      v_title := 'Request chip disetujui';
      v_body := 'Request chip IMEI ' || v_imei || ' di ' || v_store_name ||
        ' disetujui oleh ' || v_actor_name;
    else
      v_title := 'Request chip ditolak';
      v_body := 'Request chip IMEI ' || v_imei || ' di ' || v_store_name ||
        ' ditolak oleh ' || v_actor_name;
      if coalesce(trim(new.rejection_note), '') <> '' then
        v_body := v_body || '. Catatan: ' || trim(new.rejection_note);
      end if;
    end if;

    perform public.create_app_notification(
      new.promotor_id,
      coalesce(new.approved_by, new.sator_id),
      'promotor',
      'approval',
      case when new.status = 'approved'
        then 'chip_request_approved'
        else 'chip_request_rejected'
      end,
      v_title,
      v_body,
      'stock_chip_request',
      new.id::text,
      '/promotor/stok-aksi',
      jsonb_build_object('request_id', new.id),
      jsonb_build_object(
        'request_type', new.request_type,
        'store_id', new.store_id,
        'stok_id', new.stok_id,
        'imei', v_imei,
        'status', new.status
      ),
      'high',
      'chip_request_result:' || new.id::text || ':' || new.status || ':' || coalesce(new.promotor_id::text, '')
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trigger_chip_request_notifications on public.stock_chip_requests;
create trigger trigger_chip_request_notifications
after insert or update of status on public.stock_chip_requests
for each row
execute function public.handle_chip_request_notifications();
