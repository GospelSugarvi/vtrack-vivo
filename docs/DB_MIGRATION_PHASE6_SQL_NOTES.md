# Phase 6: Legacy Bonus Deprecation Guardrails

SQL file:
- [PHASE6_LEGACY_BONUS_DEPRECATION_GUARDRAILS.sql](../supabase/PHASE6_LEGACY_BONUS_DEPRECATION_GUARDRAILS.sql)

Tujuan fase ini:
- menandai kolom bonus lama sebagai `compatibility only`
- mengurangi kebingungan saat inspect schema di Supabase
- menegaskan bahwa source of truth bonus sekarang adalah `sales_bonus_events`

Object yang ditandai:
- `public.sales_sell_out.estimated_bonus`
- `public.dashboard_performance_metrics.estimated_bonus_total`
- `public.sales_bonus_events`

Catatan:
- fase ini tidak mengubah data
- fase ini tidak memutus flow lama
- fase ini hanya menambah metadata deprecation agar arah arsitektur tetap jelas
