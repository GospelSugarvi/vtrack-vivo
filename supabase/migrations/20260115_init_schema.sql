-- Enable Extensions
create extension if not exists "uuid-ossp";

-- Role Enum
create type user_role as enum ('admin', 'manager', 'spv', 'sator', 'promotor');

-- ==========================================
-- 0. UTILITY FUNCTIONS
-- ==========================================

create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Audit System
create table audit_logs (
  id uuid primary key default uuid_generate_v4(),
  table_name text not null,
  record_id uuid not null,
  operation text not null,
  old_data jsonb,
  new_data jsonb,
  changed_by uuid default auth.uid(),
  changed_at timestamptz default now()
);

create or replace function audit_record_changes()
returns trigger as $$
begin
  if (TG_OP = 'UPDATE') then
    insert into audit_logs(table_name, record_id, operation, old_data, new_data, changed_by)
    values (TG_TABLE_NAME, old.id, 'UPDATE', row_to_json(old), row_to_json(new), auth.uid());
    return new;
  elsif (TG_OP = 'DELETE') then
    insert into audit_logs(table_name, record_id, operation, old_data, changed_by)
    values (TG_TABLE_NAME, old.id, 'DELETE', row_to_json(old), auth.uid());
    return old;
  elsif (TG_OP = 'INSERT') then
    insert into audit_logs(table_name, record_id, operation, new_data, changed_by)
    values (TG_TABLE_NAME, new.id, 'INSERT', row_to_json(new), auth.uid());
    return new;
  end if;
  return null;
end;
$$ language plpgsql;

-- ==========================================
-- 1. MASTERS & HIERARCHY
-- ==========================================

create table users (
  id uuid primary key references auth.users(id),
  username text unique not null,
  full_name text not null,
  role user_role not null,
  area text,
  status text default 'active',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table stores (
  id uuid primary key default uuid_generate_v4(),
  store_name text not null,
  area text not null,
  grade text,
  address text,
  status text default 'active',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

-- Hierarchy
create table hierarchy_manager_spv (
  id uuid primary key default uuid_generate_v4(),
  manager_id uuid references users(id),
  spv_id uuid references users(id),
  active boolean default true,
  created_at timestamptz default now()
);

create table hierarchy_spv_sator (
  id uuid primary key default uuid_generate_v4(),
  spv_id uuid references users(id),
  sator_id uuid references users(id),
  active boolean default true,
  created_at timestamptz default now()
);

create table hierarchy_sator_promotor (
  id uuid primary key default uuid_generate_v4(),
  sator_id uuid references users(id),
  promotor_id uuid references users(id),
  active boolean default true,
  created_at timestamptz default now()
);

create table assignments_promotor_store (
  id uuid primary key default uuid_generate_v4(),
  promotor_id uuid references users(id),
  store_id uuid references stores(id),
  active boolean default true,
  created_at timestamptz default now()
);

-- ==========================================
-- 2. PRODUCT & INVENTORY (NEW!)
-- ==========================================

create table products (
  id uuid primary key default uuid_generate_v4(),
  model_name text not null,
  series text not null,
  image_url text,
  status text default 'active',
  
  -- Logic Flags
  is_focus boolean default false, -- Important for Target
  is_npo boolean default false,
  bonus_type text default 'range', -- Logic for Bonus Calc
  ratio_val integer default 1 check (ratio_val > 0),
  flat_bonus numeric default 0,
  
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table product_variants (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id),
  ram_rom text,
  color text,
  srp numeric not null check (srp >= 0),
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

-- Real-time Inventory Table
create table store_inventory (
  id uuid primary key default uuid_generate_v4(),
  store_id uuid references stores(id),
  variant_id uuid references product_variants(id),
  quantity integer not null default 0 check (quantity >= 0), -- Prevent negative stock
  last_updated timestamptz default now(),
  
  unique(store_id, variant_id) -- One record per variant per store
);

-- ==========================================
-- 3. TARGET SYSTEM
-- ==========================================

create table target_periods (
  id uuid primary key default uuid_generate_v4(),
  period_name text not null,
  start_date date not null,
  end_date date not null,
  status text default 'active',
  weekly_config jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table user_targets (
  id uuid primary key default uuid_generate_v4(),
  period_id uuid references target_periods(id),
  user_id uuid references users(id),
  target_omzet numeric default 0 check (target_omzet >= 0),
  target_units_focus jsonb,
  target_tiktok_follow integer default 0,
  target_vast_submissions integer default 0,
  updated_at timestamptz default now()
);

create trigger audit_user_targets_trigger
after insert or update or delete on user_targets
for each row execute function audit_record_changes();

-- ==========================================
-- 4. SALES & LOGIC AUTOMATION
-- ==========================================

create table sales_sell_out (
  id uuid primary key default uuid_generate_v4(),
  promotor_id uuid references users(id),
  store_id uuid references stores(id),
  variant_id uuid references product_variants(id),
  transaction_date date not null,
  serial_imei text unique not null,
  price_at_transaction numeric not null check (price_at_transaction > 0),
  payment_method text,
  leasing_provider text,
  status text default 'pending',
  image_proof_url text,
  
  -- Calculated Fields (Locked History)
  estimated_bonus numeric default 0, -- Auto-filled by Trigger
  
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table sales_sell_in (
  id uuid primary key default uuid_generate_v4(),
  sator_id uuid references users(id),
  store_id uuid references stores(id),
  variant_id uuid references product_variants(id),
  transaction_date date not null,
  qty integer not null check (qty > 0),
  total_value numeric not null check (total_value >= 0),
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  deleted_at timestamptz
);

create table activity_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references users(id),
  activity_type text not null,
  data jsonb,
  created_at timestamptz default now()
);

-- ==========================================
-- 5. AGGREGATION (RAPOR)
-- ==========================================

create table dashboard_performance_metrics (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references users(id),
  period_id uuid references target_periods(id),
  
  total_omzet_real numeric default 0,
  total_units_sold integer default 0,
  total_units_focus integer default 0,
  count_vast_submissions integer default 0,
  count_tiktok_follows integer default 0,
  count_promo_posts integer default 0,
  
  last_updated timestamptz default now(),
  unique(user_id, period_id)
);

-- ==========================================
-- 6. BUSINESS LOGIC TRIGGERS (THE BRAIN)
-- ==========================================

-- A. Auto-Calculate Bonus & Aggregation on Sell Out
create or replace function process_sell_out_insert()
returns trigger as $$
declare
  v_bonus numeric := 0;
  v_period_id uuid;
  v_is_focus boolean;
begin
  -- 1. Find Period
  select id into v_period_id from target_periods 
  where start_date <= new.transaction_date and end_date >= new.transaction_date limit 1;
  
  -- 2. Check Product Focus Status
  select is_focus into v_is_focus from products p
  join product_variants pv on p.id = pv.product_id
  where pv.id = new.variant_id;
  
  -- 3. Calculate Bonus (Simple Logic Placeholder - can be complex later)
  -- If product is focus, maybe give extra
  v_bonus := 5000; -- Default logic, replace with lookup to bonus_rules table later
  new.estimated_bonus := v_bonus;
  
  -- 4. Deduction Stock (Inventory)
  update store_inventory 
  set quantity = quantity - 1, last_updated = now()
  where store_id = new.store_id and variant_id = new.variant_id;
  
  -- 5. Update Aggregation (Rapor)
  insert into dashboard_performance_metrics (user_id, period_id, total_omzet_real, total_units_sold, total_units_focus)
  values (new.promotor_id, v_period_id, new.price_at_transaction, 1, case when v_is_focus then 1 else 0 end)
  on conflict (user_id, period_id) do update set
    total_omzet_real = dashboard_performance_metrics.total_omzet_real + excluded.total_omzet_real,
    total_units_sold = dashboard_performance_metrics.total_units_sold + 1,
    total_units_focus = dashboard_performance_metrics.total_units_focus + excluded.total_units_focus,
    last_updated = now();

  return new;
end;
$$ language plpgsql;

create trigger trigger_sell_out_process
before insert on sales_sell_out
for each row execute function process_sell_out_insert();

-- B. Auto-Add Stock on Sell In
create or replace function process_sell_in_insert()
returns trigger as $$
begin
  -- Update Inventory (Add Stock)
  insert into store_inventory (store_id, variant_id, quantity)
  values (new.store_id, new.variant_id, new.qty)
  on conflict (store_id, variant_id) do update set
    quantity = store_inventory.quantity + excluded.quantity,
    last_updated = now();
  return new;
end;
$$ language plpgsql;

create trigger trigger_sell_in_process
after insert on sales_sell_in
for each row execute function process_sell_in_insert();


-- ==========================================
-- 7. INDEXING & SECURITY
-- ==========================================

-- Indexes
create index idx_sales_promotor on sales_sell_out(promotor_id);
create index idx_sales_store on sales_sell_out(store_id);
create index idx_sales_variant on sales_sell_out(variant_id);
create index idx_sales_date on sales_sell_out(transaction_date);
create index idx_inventory_store on store_inventory(store_id);
create index idx_products_model on products using gin (to_tsvector('english', model_name));

-- RLS
alter table users enable row level security;
alter table stores enable row level security;
alter table sales_sell_out enable row level security;
alter table store_inventory enable row level security;
alter table dashboard_performance_metrics enable row level security;

-- Policies (Full Implementation Required)
create policy "Public Read Config" on products for select using (true);
create policy "Public Read Config 2" on product_variants for select using (true);

-- Promotor: Own Data
create policy "Promotor Own Sales" on sales_sell_out for all using (promotor_id = auth.uid());
create policy "Promotor Own Metrics" on dashboard_performance_metrics for select using (user_id = auth.uid());

-- SATOR: Team Data (Using Hierarchy)
create policy "Sator Team Sales" on sales_sell_out for select using (
  promotor_id in (
    select promotor_id from hierarchy_sator_promotor where sator_id = auth.uid()
  )
);
create policy "Sator Team Metrics" on dashboard_performance_metrics for select using (
  user_id in (
    select promotor_id from hierarchy_sator_promotor where sator_id = auth.uid()
  )
);

-- Admin: All
create policy "Admin All" on sales_sell_out for all using (
  exists (select 1 from users where id = auth.uid() and role = 'admin')
);
create policy "Admin Inventory" on store_inventory for all using (
  exists (select 1 from users where id = auth.uid() and role = 'admin')
);

