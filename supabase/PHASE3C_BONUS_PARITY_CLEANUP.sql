-- Phase 3C: Cleanup parity read model
-- Date: 2026-03-10
-- Purpose:
-- 1. Reduce noisy parity rows
-- 2. Focus parity comparison on valid user+period pairs

create or replace view public.v_bonus_parity_dashboard_vs_events as
with event_totals as (
  select
    sbe.user_id,
    sbe.period_id,
    coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus_events
  from public.sales_bonus_events sbe
  where sbe.period_id is not null
  group by sbe.user_id, sbe.period_id
),
dashboard_totals as (
  select
    dpm.user_id,
    dpm.period_id,
    coalesce(dpm.estimated_bonus_total, 0)::numeric as total_bonus_dashboard
  from public.dashboard_performance_metrics dpm
  where dpm.user_id is not null
    and dpm.period_id is not null
)
select
  dt.user_id,
  dt.period_id,
  dt.total_bonus_dashboard,
  coalesce(et.total_bonus_events, 0)::numeric as total_bonus_events,
  coalesce(et.total_bonus_events, 0)::numeric - dt.total_bonus_dashboard as bonus_gap,
  case
    when dt.total_bonus_dashboard = coalesce(et.total_bonus_events, 0)::numeric
      then 'MATCH'
    else 'MISMATCH'
  end as parity_status
from dashboard_totals dt
left join event_totals et
  on et.user_id = dt.user_id
 and et.period_id = dt.period_id;

create or replace function public.get_bonus_parity_summary()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'total_rows', count(*),
    'matched_rows', count(*) filter (where parity_status = 'MATCH'),
    'mismatched_rows', count(*) filter (where parity_status = 'MISMATCH'),
    'total_dashboard_bonus', coalesce(sum(total_bonus_dashboard), 0),
    'total_event_bonus', coalesce(sum(total_bonus_events), 0),
    'total_gap', coalesce(sum(bonus_gap), 0)
  )
  from public.v_bonus_parity_dashboard_vs_events;
$$;

