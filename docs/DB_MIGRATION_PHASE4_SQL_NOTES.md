# DB MIGRATION PHASE 4 SQL NOTES
**Date:** 10 March 2026  
**SQL Draft:** [supabase/PHASE4_CUTOVER_LEGACY_BONUS_RPC.sql](../supabase/PHASE4_CUTOVER_LEGACY_BONUS_RPC.sql)

Tujuan draft ini:
- memotong pembacaan RPC bonus lama ke source baru tanpa mengubah nama RPC di frontend

Yang dicutover:
- `get_promotor_bonus_summary(...)`
- `get_promotor_bonus_details(...)`

Keuntungan:
- app existing tidak perlu ganti nama RPC
- source baca bonus utama pindah ke ledger event
- dependency ke `sales_sell_out.estimated_bonus` berkurang

