-- Phase 3B: Backfill historical bonus events from legacy sell-out data
-- Date: 2026-03-10
-- Purpose:
-- 1. Fill sales_bonus_events for historical sales that existed before Phase 2
-- 2. Preserve parity with legacy bonus model as closely as possible
-- 3. Avoid duplicate event insertion for sales already written by Phase 2

-- Strategy:
-- - Source of historical truth for backfill = sales_sell_out.estimated_bonus
-- - Chip sales are written as bonus_type = 'chip' with amount 0
-- - Non-chip sales with estimated_bonus > 0 become bonus_type = 'range'
-- - Non-chip sales with estimated_bonus = 0 become bonus_type = 'excluded'
-- - Only backfill rows that do not yet exist in sales_bonus_events

insert into public.sales_bonus_events (
  sales_sell_out_id,
  user_id,
  period_id,
  bonus_type,
  rule_snapshot,
  bonus_amount,
  is_projection,
  calculation_version,
  notes,
  created_at,
  created_by
)
select
  sso.id as sales_sell_out_id,
  sso.promotor_id as user_id,
  tp.id as period_id,
  case
    when coalesce(sso.is_chip_sale, false) then 'chip'
    when coalesce(sso.estimated_bonus, 0) > 0 then 'range'
    else 'excluded'
  end as bonus_type,
  jsonb_build_object(
    'source', 'historical_backfill_from_sales_sell_out',
    'estimated_bonus', coalesce(sso.estimated_bonus, 0),
    'is_chip_sale', coalesce(sso.is_chip_sale, false),
    'variant_id', sso.variant_id,
    'price_at_transaction', sso.price_at_transaction
  ) as rule_snapshot,
  case
    when coalesce(sso.is_chip_sale, false) then 0
    else coalesce(sso.estimated_bonus, 0)
  end as bonus_amount,
  true as is_projection,
  'phase3_backfill_v1' as calculation_version,
  case
    when coalesce(sso.is_chip_sale, false) then 'Backfilled historical chip sale with zero bonus'
    when coalesce(sso.estimated_bonus, 0) > 0 then 'Backfilled historical bonus from sales_sell_out.estimated_bonus'
    else 'Backfilled historical excluded/zero bonus from legacy sales data'
  end as notes,
  coalesce(sso.created_at, now()) as created_at,
  sso.promotor_id as created_by
from public.sales_sell_out sso
left join public.target_periods tp
  on sso.transaction_date between tp.start_date and tp.end_date
left join public.sales_bonus_events sbe
  on sbe.sales_sell_out_id = sso.id
where sbe.id is null
  and sso.deleted_at is null;

-- Verification snapshot
select
  count(*) as total_bonus_events_after_backfill,
  count(*) filter (where calculation_version = 'phase3_backfill_v1') as backfilled_rows,
  coalesce(sum(bonus_amount), 0) as total_bonus_amount_after_backfill
from public.sales_bonus_events;

