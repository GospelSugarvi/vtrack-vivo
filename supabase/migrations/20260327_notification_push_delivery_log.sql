alter table public.app_notifications
  add column if not exists sent_push_at timestamptz,
  add column if not exists push_status text default null;

create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.app_notifications(id) on delete cascade,
  device_token_id uuid not null references public.user_device_tokens(id) on delete cascade,
  channel text not null default 'fcm',
  provider text not null default 'firebase',
  status text not null check (status in ('pending', 'sent', 'failed')),
  provider_message_id text,
  provider_response jsonb not null default '{}'::jsonb,
  error_message text,
  attempted_at timestamptz not null default now(),
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_notification_deliveries_notification
on public.notification_deliveries (notification_id, attempted_at desc);

create index if not exists idx_notification_deliveries_device
on public.notification_deliveries (device_token_id, attempted_at desc);

alter table public.notification_deliveries enable row level security;

drop policy if exists "Users can read own notification deliveries" on public.notification_deliveries;
create policy "Users can read own notification deliveries"
on public.notification_deliveries
for select
using (
  exists (
    select 1
    from public.app_notifications n
    where n.id = notification_deliveries.notification_id
      and n.recipient_user_id = auth.uid()
  )
);
