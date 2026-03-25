begin;

create extension if not exists pgcrypto;

create table if not exists public.app_roles (
  code text primary key,
  name text not null,
  sort_order integer not null default 0,
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.app_roles (code, name, sort_order, is_system)
values
  ('admin', 'Admin', 10, true),
  ('manager', 'Manager', 20, true),
  ('spv', 'SPV', 30, true),
  ('trainer', 'Trainer', 40, true),
  ('sator', 'SATOR', 50, true),
  ('promotor', 'Promotor', 60, true)
on conflict (code) do update
set
  name = excluded.name,
  sort_order = excluded.sort_order,
  is_system = excluded.is_system;

create table if not exists public.app_areas (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,
  employee_code text unique,
  full_name text not null,
  email text,
  phone text,
  status text not null default 'active' check (status in ('active', 'inactive', 'suspended')),
  home_area_id uuid references public.app_areas(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_app_users_auth_user_id on public.app_users(auth_user_id);
create index if not exists idx_app_users_home_area_id on public.app_users(home_area_id);
create index if not exists idx_app_users_status on public.app_users(status);

create table if not exists public.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id),
  role_code text not null references public.app_roles(code),
  is_primary boolean not null default false,
  active boolean not null default true,
  starts_at date not null default current_date,
  ends_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint user_role_assignments_dates_check check (ends_at is null or ends_at >= starts_at)
);

create unique index if not exists idx_user_role_assignments_unique_active
  on public.user_role_assignments(user_id, role_code, starts_at)
  where deleted_at is null;

create unique index if not exists idx_user_role_assignments_primary_role
  on public.user_role_assignments(user_id)
  where is_primary = true and active = true and deleted_at is null;

create table if not exists public.app_stores (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  area_id uuid references public.app_areas(id),
  channel text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_app_stores_area_id on public.app_stores(area_id);

create table if not exists public.user_supervisions (
  id uuid primary key default gen_random_uuid(),
  supervisor_user_id uuid not null references public.app_users(id),
  subordinate_user_id uuid not null references public.app_users(id),
  supervisor_role_code text not null references public.app_roles(code),
  subordinate_role_code text not null references public.app_roles(code),
  active boolean not null default true,
  starts_at date not null default current_date,
  ends_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint user_supervisions_self_check check (supervisor_user_id <> subordinate_user_id),
  constraint user_supervisions_dates_check check (ends_at is null or ends_at >= starts_at)
);

create unique index if not exists idx_user_supervisions_unique_active
  on public.user_supervisions(supervisor_user_id, subordinate_user_id, supervisor_role_code, subordinate_role_code, starts_at)
  where deleted_at is null;

create index if not exists idx_user_supervisions_supervisor on public.user_supervisions(supervisor_user_id)
  where active = true and deleted_at is null;

create index if not exists idx_user_supervisions_subordinate on public.user_supervisions(subordinate_user_id)
  where active = true and deleted_at is null;

create table if not exists public.store_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id),
  store_id uuid not null references public.app_stores(id),
  assignment_role_code text not null references public.app_roles(code),
  active boolean not null default true,
  starts_at date not null default current_date,
  ends_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint store_assignments_dates_check check (ends_at is null or ends_at >= starts_at)
);

create unique index if not exists idx_store_assignments_unique_active
  on public.store_assignments(user_id, store_id, assignment_role_code, starts_at)
  where deleted_at is null;

create index if not exists idx_store_assignments_user on public.store_assignments(user_id)
  where active = true and deleted_at is null;

create index if not exists idx_store_assignments_store on public.store_assignments(store_id)
  where active = true and deleted_at is null;

create table if not exists public.app_target_periods (
  id uuid primary key default gen_random_uuid(),
  period_type text not null default 'monthly' check (period_type in ('weekly', 'monthly', 'quarterly', 'yearly')),
  period_name text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'closed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint target_periods_dates_check check (end_date >= start_date)
);

create unique index if not exists idx_app_target_periods_name_unique
  on public.app_target_periods(period_type, period_name)
  where deleted_at is null;

create table if not exists public.app_target_period_weeks (
  id uuid primary key default gen_random_uuid(),
  period_id uuid not null references public.app_target_periods(id) on delete cascade,
  week_number integer not null check (week_number >= 1),
  start_date date not null,
  end_date date not null,
  weight_percent numeric(5,2) not null default 0 check (weight_percent >= 0 and weight_percent <= 100),
  working_days integer not null default 6 check (working_days between 1 and 7),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint target_period_weeks_dates_check check (end_date >= start_date)
);

create unique index if not exists idx_app_target_period_weeks_unique
  on public.app_target_period_weeks(period_id, week_number)
  where deleted_at is null;

create table if not exists public.app_user_targets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id),
  period_id uuid not null references public.app_target_periods(id) on delete cascade,
  role_code text not null references public.app_roles(code),
  sell_out_target numeric(18,2) not null default 0,
  sell_in_target numeric(18,2) not null default 0,
  focus_target numeric(18,2) not null default 0,
  new_outlet_target numeric(18,2) not null default 0,
  visit_target numeric(18,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_app_user_targets_unique_period
  on public.app_user_targets(user_id, period_id, role_code)
  where deleted_at is null;

create or replace view public.v_user_primary_role as
select
  u.id as user_id,
  u.full_name,
  ura.role_code,
  ura.active
from public.app_users u
join public.user_role_assignments ura
  on ura.user_id = u.id
 and ura.is_primary = true
 and ura.active = true
 and ura.deleted_at is null
where u.deleted_at is null;

create or replace view public.v_active_supervision as
select
  us.id,
  us.supervisor_user_id,
  supervisor.full_name as supervisor_name,
  us.supervisor_role_code,
  us.subordinate_user_id,
  subordinate.full_name as subordinate_name,
  us.subordinate_role_code
from public.user_supervisions us
join public.app_users supervisor on supervisor.id = us.supervisor_user_id
join public.app_users subordinate on subordinate.id = us.subordinate_user_id
where us.active = true
  and us.deleted_at is null
  and supervisor.deleted_at is null
  and subordinate.deleted_at is null;

create or replace view public.v_active_store_assignment as
select
  sa.id,
  sa.user_id,
  u.full_name,
  sa.assignment_role_code,
  sa.store_id,
  s.name as store_name
from public.store_assignments sa
join public.app_users u on u.id = sa.user_id
join public.app_stores s on s.id = sa.store_id
where sa.active = true
  and sa.deleted_at is null
  and u.deleted_at is null
  and s.deleted_at is null;

comment on table public.app_users is 'Master user aplikasi baru. Satu baris per orang.';
comment on table public.user_role_assignments is 'Role user yang aktif. Bisa lebih dari satu role bila dibutuhkan.';
comment on table public.user_supervisions is 'Hierarchy generik atasan ke bawahan untuk semua role.';
comment on table public.store_assignments is 'Assignment user ke toko berdasarkan role penugasan.';
comment on table public.app_target_periods is 'Periode target resmi.';
comment on table public.app_target_period_weeks is 'Pembagian minggu dalam satu periode target.';
comment on table public.app_user_targets is 'Target resmi per user per periode.';

commit;
