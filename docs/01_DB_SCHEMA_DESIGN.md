# DATABASE SCHEMA DESIGN 2026
**Status:** DRAFT (Implementation Ready)
**Target DB:** Supabase (PostgreSQL)

---

## 1. USER & HIERARCHY

```sql
-- Role Enum
create type user_role as enum ('admin', 'manager', 'spv', 'sator', 'promotor');

-- Base User Profile
create table users (
  id uuid primary key references auth.users(id),
  username text unique not null,
  full_name text not null,
  role user_role not null,
  area text, -- e.g. "Makassar" (Flexible)
  status text default 'active', -- active, inactive
  created_at timestamptz default now()
);

-- Store/Toko
create table stores (
  id uuid primary key default uuid_generate_v4(),
  store_name text not null,
  area text not null, -- grouping area
  grade text, -- A, B, C
  address text,
  status text default 'active'
);

-- Hierarchy Assignments (One-to-Many)
-- Manager -> SPV
create table hierarchy_manager_spv (
  id uuid primary key default uuid_generate_v4(),
  manager_id uuid references users(id),
  spv_id uuid references users(id),
  active boolean default true
);

-- SPV -> SATOR
create table hierarchy_spv_sator (
  id uuid primary key default uuid_generate_v4(),
  spv_id uuid references users(id),
  sator_id uuid references users(id),
  active boolean default true
);

-- SATOR -> Promotor
create table hierarchy_sator_promotor (
  id uuid primary key default uuid_generate_v4(),
  sator_id uuid references users(id),
  promotor_id uuid references users(id),
  active boolean default true
);

-- Promotor -> Toko (Workplace)
create table assignments_promotor_store (
  id uuid primary key default uuid_generate_v4(),
  promotor_id uuid references users(id),
  store_id uuid references stores(id),
  active boolean default true
);
```

---

## 2. PRODUCT MANAGEMENT

```sql
-- Product Master
create table products (
  id uuid primary key default uuid_generate_v4(),
  model_name text not null, -- e.g. "Y29 4G"
  series text not null, -- Y-Series, V-Series, X-Series
  image_url text,
  status text default 'active',
  
  -- Business Flags (Dynamic)
  is_focus boolean default false,
  is_npo boolean default false, -- New Product Order
  bonus_type text default 'range', -- range, flat, ratio
  ratio_val integer default 1, -- 2 for 2:1 ratio
  flat_bonus numeric default 0, -- if type is flat
  
  created_at timestamptz default now()
);

-- Product Variants (SKU Level)
create table product_variants (
  id uuid primary key default uuid_generate_v4(),
  product_id uuid references products(id),
  ram_rom text, -- "8GB/128GB"
  color text, -- "Hitam"
  srp numeric not null, -- Harga Resmi
  active boolean default true
);

-- Price History (Audit)
create table product_price_history (
  id uuid primary key default uuid_generate_v4(),
  variant_id uuid references product_variants(id),
  old_price numeric,
  new_price numeric,
  effective_date timestamptz default now(),
  changed_by uuid references users(id)
);
```

---

## 3. TARGET SYSTEM

```sql
-- Target Periods (Monthly)
create table target_periods (
  id uuid primary key default uuid_generate_v4(),
  period_name text not null, -- "2026-01"
  start_date date not null,
  end_date date not null,
  status text default 'active', -- active, locked
  
  -- Weekly Config (JSON)
  -- { "w1": 30, "w2": 25, "w3": 20, "w4": 25 }
  weekly_config jsonb,
  
  -- Flags Types Active
  is_focus_active boolean default true,
  is_tiktok_active boolean default false
);

-- User Targets (All Levels)
create table user_targets (
  id uuid primary key default uuid_generate_v4(),
  period_id uuid references target_periods(id),
  user_id uuid references users(id), -- Applicable to Promotor, SATOR, SPV, Manager
  role_at_time user_role not null, -- Snapshot role
  
  -- Target Values
  target_omzet numeric default 0, -- Sell Out All (Rp)
  target_sell_in numeric default 0, -- Sell In All (Rp)
  
  -- Specific Product Targets (JSON)
  -- { "Y400": 10, "Y29": 20 }
  target_units_focus jsonb, 
  
  -- Social Media
  target_tiktok_follow integer default 0,
  
  updated_at timestamptz default now()
);
```

---

## 4. SALES & REPORTING (TRANSACTIONS)

```sql
-- Sell Out (Penjualan Promotor)
create table sales_sell_out (
  id uuid primary key default uuid_generate_v4(),
  promotor_id uuid references users(id),
  store_id uuid references stores(id),
  variant_id uuid references product_variants(id),
  
  transaction_date date not null,
  serial_imei text unique not null,
  price_at_transaction numeric not null, -- Snapshot price
  
  payment_method text, -- CASH, LEASING
  leasing_provider text, -- VAST, HCI, etc (if leasing)
  customer_name text,
  
  status text default 'pending', -- pending, approved, rejected
  image_proof_url text,
  
  created_at timestamptz default now()
);

-- Sell In (Order Toko)
create table sales_sell_in (
  id uuid primary key default uuid_generate_v4(),
  sator_id uuid references users(id), -- SATOR inputs/verified
  store_id uuid references stores(id),
  variant_id uuid references product_variants(id),
  
  transaction_date date not null,
  qty integer not null,
  total_value numeric not null,
  
  notes text,
  created_at timestamptz default now()
);

-- Activity Logs (Absensi, Validasi Stok, etc)
create table activity_logs (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references users(id),
  activity_type text not null, -- clock_in, stock_check, promosi
  store_id uuid references stores(id),
  
  data jsonb, -- { "lat": ..., "long": ..., "url": ... }
  created_at timestamptz default now()
);
```

---

## 5. BONUS CONFIGURATION

```sql
-- Bonus Rules: Range Based
create table bonus_rules_range (
  id uuid primary key default uuid_generate_v4(),
  user_type text not null, -- official, training, sator, spv
  price_min numeric not null,
  price_max numeric not null,
  bonus_value numeric not null, -- Rupiah (Promotor) or Points (SATOR/SPV)
  currency text default 'IDR', -- IDR or POINT
  active boolean default true
);

-- Bonus Rules: Products & Repo
create table bonus_special_rules (
  id uuid primary key default uuid_generate_v4(),
  period_id uuid references target_periods(id),
  product_model text not null, -- e.g "Y400 Series"
  
  -- Reward Tiers (JSON)
  -- [ { "min": 0, "max": 50, "reward": 750000 }, ... ]
  reward_tiers jsonb,
  
  -- Penalty
  penalty_threshold_percent integer default 80,
  penalty_amount numeric default 0,
  
  active boolean default true
);

-- KPI Bobot Settings
create table bonus_kpi_settings (
  id uuid primary key default uuid_generate_v4(),
  role text not null, -- sator, spv
  
  weight_sell_out numeric default 40,
  weight_sell_in numeric default 30, -- 20 for sator
  weight_focus numeric default 20, -- 30 for sator
  weight_kpi_ma numeric default 10,
  
  active boolean default true
);

-- KPI MA Scores (Individual)
create table bonus_kpi_ma_scores (
  id uuid primary key default uuid_generate_v4(),
  period_id uuid references target_periods(id),
  user_id uuid references users(id), -- SATOR or SPV
  score_percent numeric not null, -- 0-10%
  assessor_id uuid references users(id) -- Manager who assessed
);
```

---

## 6. NOTIFICATIONS & ALERTS

```sql
create table notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references users(id),
  title text not null,
  message text not null,
  type text not null, -- alert, info, bonus, target
  is_read boolean default false,
  action_link text, -- deep link
  created_at timestamptz default now()
);
```

---

**Next Steps:**
1. Create Migration File (`supabase/migrations/20260114_init_schema.sql`)
2. Set up RLS Policies
3. Insert Master Data (Products, Users)
