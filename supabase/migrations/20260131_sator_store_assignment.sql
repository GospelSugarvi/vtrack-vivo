-- Create table for SATOR → STORE assignment
create table if not exists assignments_sator_store (
  id uuid primary key default uuid_generate_v4(),
  sator_id uuid references users(id) not null,
  store_id uuid references stores(id) not null,
  active boolean default true,
  created_at timestamptz default now(),
  
  unique(sator_id, store_id)
);

-- Index for performance
create index idx_assignments_sator_store_sator on assignments_sator_store(sator_id) where active = true;
create index idx_assignments_sator_store_store on assignments_sator_store(store_id) where active = true;

-- RLS Policies
alter table assignments_sator_store enable row level security;

-- Admin can manage all
create policy "Admin can manage sator-store assignments"
  on assignments_sator_store for all
  using (exists (select 1 from users where id = auth.uid() and role = 'admin'));

-- Sator can view their own assignments
create policy "Sator can view own store assignments"
  on assignments_sator_store for select
  using (sator_id = auth.uid());

-- Grant permissions
grant select, insert, update, delete on assignments_sator_store to authenticated;
