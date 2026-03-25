# DB MIGRATION PHASE 3 SQL NOTES
**Date:** 10 March 2026  
**SQL Draft:** [supabase/PHASE3_BONUS_READ_MODEL_AND_PARITY.sql](../supabase/PHASE3_BONUS_READ_MODEL_AND_PARITY.sql)

Tujuan draft ini:
- membangun read model bonus dari `sales_bonus_events`
- membuat function bonus summary/detail berbasis event ledger
- menyediakan parity view antara ledger baru dan dashboard legacy

Cakupan:
- `v_bonus_summary_from_events`
- `v_bonus_event_details`
- `get_promotor_bonus_summary_from_events(...)`
- `get_promotor_bonus_details_from_events(...)`
- `v_bonus_parity_dashboard_vs_events`
- `get_bonus_parity_summary()`

Catatan penting:
- draft ini belum memindahkan function legacy lama
- dashboard existing masih boleh tetap baca `dashboard_performance_metrics`
- tujuan fase ini adalah menyiapkan jalur baca baru dan alat rekonsiliasi

Setelah apply:
- lakukan parity check
- jika mismatch besar, investigasi logika bonus legacy vs ledger dual-write
- jika parity cukup stabil, baru tahap berikutnya memindahkan pembacaan UI/reporting

