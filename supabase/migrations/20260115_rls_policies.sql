-- =============================================
-- FIXED RLS POLICIES FOR VTRACK
-- No infinite recursion
-- Run this in Supabase SQL Editor
-- =============================================

-- Drop ALL existing policies first
drop policy if exists "Users read own profile" on users;
drop policy if exists "Admin read all users" on users;
drop policy if exists "Admin manage users" on users;
drop policy if exists "Anyone can read products" on products;
drop policy if exists "Anyone can read variants" on product_variants;
drop policy if exists "Admin manage products" on products;
drop policy if exists "Admin manage variants" on product_variants;
drop policy if exists "Promotor own sales" on sales_sell_out;
drop policy if exists "Sator team sales" on sales_sell_out;
drop policy if exists "SPV area sales" on sales_sell_out;
drop policy if exists "Admin all sales" on sales_sell_out;
drop policy if exists "User own metrics" on dashboard_performance_metrics;
drop policy if exists "Sator team metrics" on dashboard_performance_metrics;
drop policy if exists "Admin all metrics" on dashboard_performance_metrics;
drop policy if exists "Authenticated read inventory" on store_inventory;
drop policy if exists "Admin manage inventory" on store_inventory;
drop policy if exists "Authenticated read stores" on stores;
drop policy if exists "Admin manage stores" on stores;
drop policy if exists "Public can read usernames" on users;
drop policy if exists "Read Users" on users;
drop policy if exists "Sales Own" on sales_sell_out;
drop policy if exists "Aggregates Own" on dashboard_performance_metrics;
drop policy if exists "Audit Admin" on audit_logs;
drop policy if exists "Public Read Config" on products;
drop policy if exists "Public Read Config 2" on product_variants;
drop policy if exists "Promotor Own Sales" on sales_sell_out;
drop policy if exists "Promotor Own Metrics" on dashboard_performance_metrics;
drop policy if exists "Sator Team Sales" on sales_sell_out;
drop policy if exists "Sator Team Metrics" on dashboard_performance_metrics;
drop policy if exists "Admin All" on sales_sell_out;
drop policy if exists "Admin Inventory" on store_inventory;

-- =============================================
-- USERS TABLE
-- Simple: authenticated users can read their own row
-- =============================================
create policy "Users read own"
on users for select
using (auth.uid() = id);

-- For admin to read all, we use service role or RPC
-- Don't query users table from users policy (infinite recursion)

-- =============================================
-- PRODUCTS & VARIANTS (Public Read - catalog data)
-- =============================================
create policy "Read products"
on products for select
using (auth.role() = 'authenticated');

create policy "Read variants"
on product_variants for select
using (auth.role() = 'authenticated');

-- =============================================
-- STORES
-- =============================================
create policy "Read stores"
on stores for select
using (auth.role() = 'authenticated');

-- =============================================
-- SALES_SELL_OUT
-- =============================================
create policy "Sales own"
on sales_sell_out for select
using (promotor_id = auth.uid());

create policy "Sales insert own"
on sales_sell_out for insert
with check (promotor_id = auth.uid());

-- =============================================
-- DASHBOARD_PERFORMANCE_METRICS
-- =============================================
create policy "Metrics own"
on dashboard_performance_metrics for select
using (user_id = auth.uid());

-- =============================================
-- STORE_INVENTORY
-- =============================================
create policy "Inventory read"
on store_inventory for select
using (auth.role() = 'authenticated');

-- =============================================
-- HIERARCHY TABLES (needed for team visibility)
-- =============================================
alter table hierarchy_manager_spv enable row level security;
alter table hierarchy_spv_sator enable row level security;
alter table hierarchy_sator_promotor enable row level security;
alter table assignments_promotor_store enable row level security;

create policy "Hierarchy read"
on hierarchy_manager_spv for select
using (auth.role() = 'authenticated');

create policy "Hierarchy read 2"
on hierarchy_spv_sator for select
using (auth.role() = 'authenticated');

create policy "Hierarchy read 3"
on hierarchy_sator_promotor for select
using (auth.role() = 'authenticated');

create policy "Assignments read"
on assignments_promotor_store for select
using (auth.role() = 'authenticated');
