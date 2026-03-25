begin;

create table if not exists public.fact_sell_out (
  id uuid primary key default gen_random_uuid(),
  transaction_at timestamptz not null,
  transaction_date date not null,
  promotor_user_id uuid not null references public.app_users(id),
  store_id uuid not null references public.app_stores(id),
  spv_user_id uuid references public.app_users(id),
  sator_user_id uuid references public.app_users(id),
  product_id uuid,
  brand_id uuid,
  qty integer not null default 0,
  amount numeric(18,2) not null default 0,
  is_focus_product boolean not null default false,
  is_special_type boolean not null default false,
  period_id uuid references public.app_target_periods(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_fact_sell_out_promotor_date on public.fact_sell_out(promotor_user_id, transaction_date);
create index if not exists idx_fact_sell_out_store_date on public.fact_sell_out(store_id, transaction_date);
create index if not exists idx_fact_sell_out_sator_date on public.fact_sell_out(sator_user_id, transaction_date);
create index if not exists idx_fact_sell_out_spv_date on public.fact_sell_out(spv_user_id, transaction_date);
create index if not exists idx_fact_sell_out_period on public.fact_sell_out(period_id);

create table if not exists public.fact_sell_in (
  id uuid primary key default gen_random_uuid(),
  transaction_at timestamptz not null,
  transaction_date date not null,
  sator_user_id uuid not null references public.app_users(id),
  store_id uuid not null references public.app_stores(id),
  amount numeric(18,2) not null default 0,
  qty integer not null default 0,
  period_id uuid references public.app_target_periods(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_fact_sell_in_sator_date on public.fact_sell_in(sator_user_id, transaction_date);
create index if not exists idx_fact_sell_in_store_date on public.fact_sell_in(store_id, transaction_date);
create index if not exists idx_fact_sell_in_period on public.fact_sell_in(period_id);

create table if not exists public.fact_attendance (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id),
  attendance_date date not null,
  clock_in_at timestamptz,
  clock_out_at timestamptz,
  status text not null default 'present' check (status in ('present', 'late', 'absent', 'leave')),
  created_at timestamptz not null default now(),
  unique (user_id, attendance_date)
);

create index if not exists idx_fact_attendance_date on public.fact_attendance(attendance_date);

create table if not exists public.fact_visit (
  id uuid primary key default gen_random_uuid(),
  visit_date date not null,
  sator_user_id uuid not null references public.app_users(id),
  store_id uuid not null references public.app_stores(id),
  visit_status text not null default 'completed' check (visit_status in ('planned', 'completed', 'missed', 'cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists idx_fact_visit_sator_date on public.fact_visit(sator_user_id, visit_date);
create index if not exists idx_fact_visit_store_date on public.fact_visit(store_id, visit_date);

create table if not exists public.fact_stock_event (
  id uuid primary key default gen_random_uuid(),
  event_at timestamptz not null,
  event_date date not null,
  store_id uuid not null references public.app_stores(id),
  actor_user_id uuid not null references public.app_users(id),
  event_type text not null check (
    event_type in (
      'stock_opname',
      'stock_adjustment',
      'stock_transfer_in',
      'stock_transfer_out',
      'stock_validation',
      'stock_return'
    )
  ),
  product_id uuid,
  qty integer not null default 0,
  reference_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_fact_stock_event_store_date on public.fact_stock_event(store_id, event_date);
create index if not exists idx_fact_stock_event_actor_date on public.fact_stock_event(actor_user_id, event_date);

create table if not exists public.summary_user_daily (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id),
  role_code text not null references public.app_roles(code),
  summary_date date not null,
  spv_user_id uuid references public.app_users(id),
  sator_user_id uuid references public.app_users(id),
  store_id uuid references public.app_stores(id),
  sell_out_all_type_actual numeric(18,2) not null default 0,
  focus_product_actual integer not null default 0,
  special_type_actual integer not null default 0,
  sell_in_actual numeric(18,2) not null default 0,
  attendance_status text,
  visit_count integer not null default 0,
  activity_score integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, role_code, summary_date)
);

create index if not exists idx_summary_user_daily_role_date on public.summary_user_daily(role_code, summary_date);
create index if not exists idx_summary_user_daily_sator_date on public.summary_user_daily(sator_user_id, summary_date);
create index if not exists idx_summary_user_daily_spv_date on public.summary_user_daily(spv_user_id, summary_date);

create table if not exists public.summary_store_daily (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.app_stores(id),
  summary_date date not null,
  sell_out_all_type_actual numeric(18,2) not null default 0,
  focus_product_actual integer not null default 0,
  sell_in_actual numeric(18,2) not null default 0,
  active_promotor_count integer not null default 0,
  visit_count integer not null default 0,
  stock_event_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, summary_date)
);

create index if not exists idx_summary_store_daily_date on public.summary_store_daily(summary_date);

create table if not exists public.summary_team_daily (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.app_users(id),
  owner_role_code text not null references public.app_roles(code),
  summary_date date not null,
  sell_out_all_type_actual numeric(18,2) not null default 0,
  focus_product_actual integer not null default 0,
  sell_in_actual numeric(18,2) not null default 0,
  active_member_count integer not null default 0,
  inactive_member_count integer not null default 0,
  active_store_count integer not null default 0,
  pending_approval_count integer not null default 0,
  blocked_work_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_user_id, owner_role_code, summary_date)
);

create index if not exists idx_summary_team_daily_role_date on public.summary_team_daily(owner_role_code, summary_date);

create table if not exists public.summary_user_period (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id),
  role_code text not null references public.app_roles(code),
  period_id uuid not null references public.app_target_periods(id) on delete cascade,
  sell_out_all_type_target numeric(18,2) not null default 0,
  sell_out_all_type_actual numeric(18,2) not null default 0,
  focus_product_target numeric(18,2) not null default 0,
  focus_product_actual numeric(18,2) not null default 0,
  sell_in_target numeric(18,2) not null default 0,
  sell_in_actual numeric(18,2) not null default 0,
  achievement_pct_sell_out_all_type numeric(7,2) not null default 0,
  achievement_pct_focus_product numeric(7,2) not null default 0,
  achievement_pct_sell_in numeric(7,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, role_code, period_id)
);

create index if not exists idx_summary_user_period_role_period on public.summary_user_period(role_code, period_id);

create table if not exists public.summary_team_period (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.app_users(id),
  owner_role_code text not null references public.app_roles(code),
  period_id uuid not null references public.app_target_periods(id) on delete cascade,
  sell_out_all_type_target numeric(18,2) not null default 0,
  sell_out_all_type_actual numeric(18,2) not null default 0,
  focus_product_target numeric(18,2) not null default 0,
  focus_product_actual numeric(18,2) not null default 0,
  sell_in_target numeric(18,2) not null default 0,
  sell_in_actual numeric(18,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_user_id, owner_role_code, period_id)
);

create index if not exists idx_summary_team_period_role_period on public.summary_team_period(owner_role_code, period_id);

create table if not exists public.summary_leaderboard_daily (
  id uuid primary key default gen_random_uuid(),
  summary_date date not null,
  scope_code text not null,
  scope_role_code text not null references public.app_roles(code),
  scope_user_id uuid references public.app_users(id),
  ranked_user_id uuid not null references public.app_users(id),
  ranked_role_code text not null references public.app_roles(code),
  rank_position integer not null,
  score_sell_out_all_type_pct numeric(7,2) not null default 0,
  score_focus_product_pct numeric(7,2) not null default 0,
  final_score numeric(7,2) not null default 0,
  created_at timestamptz not null default now(),
  unique (summary_date, scope_code, ranked_user_id, ranked_role_code)
);

create index if not exists idx_summary_leaderboard_daily_scope on public.summary_leaderboard_daily(scope_code, summary_date, rank_position);

create table if not exists public.summary_leaderboard_period (
  id uuid primary key default gen_random_uuid(),
  period_kind text not null check (period_kind in ('weekly', 'monthly')),
  period_id uuid not null references public.app_target_periods(id) on delete cascade,
  scope_code text not null,
  scope_role_code text not null references public.app_roles(code),
  scope_user_id uuid references public.app_users(id),
  ranked_user_id uuid not null references public.app_users(id),
  ranked_role_code text not null references public.app_roles(code),
  rank_position integer not null,
  score_sell_out_all_type_pct numeric(7,2) not null default 0,
  score_focus_product_pct numeric(7,2) not null default 0,
  final_score numeric(7,2) not null default 0,
  created_at timestamptz not null default now(),
  unique (period_kind, period_id, scope_code, ranked_user_id, ranked_role_code)
);

create index if not exists idx_summary_leaderboard_period_scope on public.summary_leaderboard_period(scope_code, period_id, rank_position);

create table if not exists public.summary_recalc_queue (
  id uuid primary key default gen_random_uuid(),
  summary_kind text not null check (
    summary_kind in (
      'user_daily',
      'store_daily',
      'team_daily',
      'user_period',
      'team_period',
      'leaderboard_daily',
      'leaderboard_period'
    )
  ),
  entity_type text not null,
  entity_id uuid,
  target_date date,
  target_period_id uuid references public.app_target_periods(id),
  status text not null default 'queued' check (status in ('queued', 'processing', 'done', 'failed')),
  attempt_count integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists idx_summary_recalc_queue_status_created on public.summary_recalc_queue(status, created_at);

create table if not exists public.motivational_posts (
  id uuid primary key default gen_random_uuid(),
  period_kind text not null check (period_kind in ('daily', 'weekly', 'monthly')),
  category_code text not null check (category_code in ('sell_out_all_type', 'focus_product')),
  scope_user_id uuid references public.app_users(id),
  winner_user_ids uuid[] not null default '{}',
  image_path text,
  posted_room_id uuid,
  scheduled_at timestamptz not null,
  posted_at timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled', 'generated', 'posted', 'failed')),
  created_at timestamptz not null default now()
);

create index if not exists idx_motivational_posts_schedule on public.motivational_posts(status, scheduled_at);

comment on table public.fact_sell_out is 'Raw sell out transactions for rebuild architecture.';
comment on table public.fact_sell_in is 'Raw sell in transactions for rebuild architecture.';
comment on table public.summary_user_daily is 'Daily user summary for fast dashboard reads.';
comment on table public.summary_team_daily is 'Daily aggregated summary by owner role.';
comment on table public.summary_leaderboard_daily is 'Daily leaderboard snapshots per scope.';
comment on table public.summary_recalc_queue is 'Queue for asynchronous summary recalculation.';
comment on table public.motivational_posts is 'Auto-generated best performance poster jobs and results.';

commit;
