-- Phase 6
-- Mark legacy bonus columns as compatibility-only to reduce future confusion.
-- This phase is additive and safe to run multiple times.

comment on column public.sales_sell_out.estimated_bonus is
'LEGACY COMPATIBILITY ONLY. Do not use as source of truth for bonus. Source of truth = public.sales_bonus_events. Keep temporarily for compatibility and historical backfill.';

comment on column public.dashboard_performance_metrics.estimated_bonus_total is
'LEGACY COMPATIBILITY ONLY. Do not use as source of truth for bonus dashboards. Source of truth = public.sales_bonus_events via bonus read-model functions/views.';

comment on table public.sales_bonus_events is
'Source of truth for bonus events and bonus reporting. Use this table and its derived read models for bonus calculations, feeds, leaderboard, and reconciliation.';
