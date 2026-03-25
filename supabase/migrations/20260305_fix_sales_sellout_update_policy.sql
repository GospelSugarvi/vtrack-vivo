-- Fix: allow promotor to update their own sales row (needed for async image_proof_url update)
-- Date: 2026-03-05

-- Ensure RLS is enabled
alter table if exists public.sales_sell_out enable row level security;

-- Idempotent: recreate explicit update policy for own row
drop policy if exists "Sales update own" on public.sales_sell_out;
create policy "Sales update own"
on public.sales_sell_out
for update
using (promotor_id = auth.uid())
with check (promotor_id = auth.uid());

