-- Phase 1: Core ledger and governance tables
-- Date: 2026-03-10
-- Purpose:
-- 1. Add missing event/history ledger tables
-- 2. Add governance tables
-- 3. Add baseline indexes
-- 4. Enable baseline RLS for new frontend-facing tables
--
-- Notes:
-- - Safe additive migration only
-- - Does not remove or rename existing objects
-- - Existing flows remain operational

create extension if not exists "uuid-ossp";

-- =========================================================
-- 1. BONUS EVENT LEDGER
-- =========================================================

create table if not exists public.sales_bonus_events (
  id uuid primary key default uuid_generate_v4(),
  sales_sell_out_id uuid not null references public.sales_sell_out(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete restrict,
  period_id uuid references public.target_periods(id) on delete set null,
  bonus_type text not null,
  rule_id uuid,
  rule_snapshot jsonb,
  bonus_amount numeric not null default 0 check (bonus_amount >= 0),
  is_projection boolean not null default true,
  calculation_version text not null default 'v1',
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null,
  constraint sales_bonus_events_bonus_type_check
    check (bonus_type in ('range', 'flat', 'ratio', 'chip', 'adjustment', 'excluded'))
);

create index if not exists idx_sales_bonus_events_sale
  on public.sales_bonus_events(sales_sell_out_id);

create index if not exists idx_sales_bonus_events_user_period
  on public.sales_bonus_events(user_id, period_id);

create index if not exists idx_sales_bonus_events_period_user
  on public.sales_bonus_events(period_id, user_id);

create index if not exists idx_sales_bonus_events_created_at
  on public.sales_bonus_events(created_at desc);

-- =========================================================
-- 2. SELL OUT STATUS HISTORY
-- =========================================================

create table if not exists public.sales_sell_out_status_history (
  id uuid primary key default uuid_generate_v4(),
  sales_sell_out_id uuid not null references public.sales_sell_out(id) on delete cascade,
  old_status text,
  new_status text not null,
  notes text,
  changed_at timestamptz not null default now(),
  changed_by uuid references public.users(id) on delete set null
);

create index if not exists idx_sales_sell_out_status_history_sale_changed
  on public.sales_sell_out_status_history(sales_sell_out_id, changed_at desc);

-- =========================================================
-- 3. SELL IN ORDER STATUS HISTORY
-- =========================================================

create table if not exists public.sell_in_order_status_history (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.sell_in_orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  notes text,
  changed_at timestamptz not null default now(),
  changed_by uuid references public.users(id) on delete set null
);

create index if not exists idx_sell_in_order_status_history_order_changed
  on public.sell_in_order_status_history(order_id, changed_at desc);

-- =========================================================
-- 4. CHIP REQUEST STATUS HISTORY
-- =========================================================

create table if not exists public.stock_chip_request_history (
  id uuid primary key default uuid_generate_v4(),
  stock_chip_request_id uuid not null references public.stock_chip_requests(id) on delete cascade,
  old_status text,
  new_status text not null,
  notes text,
  changed_at timestamptz not null default now(),
  changed_by uuid references public.users(id) on delete set null
);

create index if not exists idx_stock_chip_request_history_request_changed
  on public.stock_chip_request_history(stock_chip_request_id, changed_at desc);

-- =========================================================
-- 5. GOVERNANCE TABLES
-- =========================================================

create table if not exists public.error_logs (
  id uuid primary key default uuid_generate_v4(),
  error_code text,
  error_message text not null,
  error_context jsonb,
  endpoint text,
  user_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_error_logs_created_at
  on public.error_logs(created_at desc);

create index if not exists idx_error_logs_user_created_at
  on public.error_logs(user_id, created_at desc);

create index if not exists idx_error_logs_code_created_at
  on public.error_logs(error_code, created_at desc);

create table if not exists public.job_runs (
  id uuid primary key default uuid_generate_v4(),
  job_name text not null,
  status text not null default 'running'
    check (status in ('running', 'success', 'failed', 'cancelled')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  metadata jsonb,
  error_message text,
  triggered_by uuid references public.users(id) on delete set null
);

create index if not exists idx_job_runs_job_name_started
  on public.job_runs(job_name, started_at desc);

create index if not exists idx_job_runs_status_started
  on public.job_runs(status, started_at desc);

create table if not exists public.idempotency_keys (
  id uuid primary key default uuid_generate_v4(),
  idempotency_key text not null unique,
  scope text not null,
  request_hash text,
  response_payload jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);

create index if not exists idx_idempotency_keys_created_at
  on public.idempotency_keys(created_at desc);

create table if not exists public.rule_snapshots (
  id uuid primary key default uuid_generate_v4(),
  rule_domain text not null,
  source_rule_id uuid,
  snapshot_data jsonb not null,
  version_label text,
  created_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null
);

create index if not exists idx_rule_snapshots_domain_created
  on public.rule_snapshots(rule_domain, created_at desc);

create table if not exists public.recalc_requests (
  id uuid primary key default uuid_generate_v4(),
  request_type text not null,
  target_scope jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'running', 'completed', 'failed', 'cancelled')),
  requested_by uuid references public.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  notes text
);

create index if not exists idx_recalc_requests_status_requested
  on public.recalc_requests(status, requested_at desc);

-- =========================================================
-- 6. BASELINE RLS
-- =========================================================

alter table public.sales_bonus_events enable row level security;
alter table public.sales_sell_out_status_history enable row level security;
alter table public.sell_in_order_status_history enable row level security;
alter table public.stock_chip_request_history enable row level security;
alter table public.error_logs enable row level security;
alter table public.job_runs enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.rule_snapshots enable row level security;
alter table public.recalc_requests enable row level security;

drop policy if exists "Users read own sales bonus events" on public.sales_bonus_events;
create policy "Users read own sales bonus events"
on public.sales_bonus_events
for select
to authenticated
using (user_id = auth.uid() or public.is_admin_user());

drop policy if exists "Admins manage sales bonus events" on public.sales_bonus_events;
create policy "Admins manage sales bonus events"
on public.sales_bonus_events
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Users read own sell out status history" on public.sales_sell_out_status_history;
create policy "Users read own sell out status history"
on public.sales_sell_out_status_history
for select
to authenticated
using (
  exists (
    select 1
    from public.sales_sell_out sso
    where sso.id = sales_sell_out_status_history.sales_sell_out_id
      and (sso.promotor_id = auth.uid() or public.is_elevated_user())
  )
);

drop policy if exists "Admins manage sell out status history" on public.sales_sell_out_status_history;
create policy "Admins manage sell out status history"
on public.sales_sell_out_status_history
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Users read own sell in order status history" on public.sell_in_order_status_history;
create policy "Users read own sell in order status history"
on public.sell_in_order_status_history
for select
to authenticated
using (
  exists (
    select 1
    from public.sell_in_orders sio
    where sio.id = sell_in_order_status_history.order_id
      and (sio.sator_id = auth.uid() or public.is_elevated_user())
  )
);

drop policy if exists "Admins manage sell in order status history" on public.sell_in_order_status_history;
create policy "Admins manage sell in order status history"
on public.sell_in_order_status_history
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Users read own chip request history" on public.stock_chip_request_history;
create policy "Users read own chip request history"
on public.stock_chip_request_history
for select
to authenticated
using (
  exists (
    select 1
    from public.stock_chip_requests scr
    where scr.id = stock_chip_request_history.stock_chip_request_id
      and (
        scr.promotor_id = auth.uid()
        or scr.sator_id = auth.uid()
        or public.is_elevated_user()
      )
  )
);

drop policy if exists "Admins manage chip request history" on public.stock_chip_request_history;
create policy "Admins manage chip request history"
on public.stock_chip_request_history
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Admins manage error logs" on public.error_logs;
create policy "Admins manage error logs"
on public.error_logs
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Admins manage job runs" on public.job_runs;
create policy "Admins manage job runs"
on public.job_runs
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Admins manage idempotency keys" on public.idempotency_keys;
create policy "Admins manage idempotency keys"
on public.idempotency_keys
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Admins manage rule snapshots" on public.rule_snapshots;
create policy "Admins manage rule snapshots"
on public.rule_snapshots
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "Admins manage recalc requests" on public.recalc_requests;
create policy "Admins manage recalc requests"
on public.recalc_requests
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

