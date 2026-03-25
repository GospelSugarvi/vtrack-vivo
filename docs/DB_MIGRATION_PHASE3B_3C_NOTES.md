# DB MIGRATION PHASE 3B/3C NOTES
**Date:** 10 March 2026  
**SQL Drafts:**  
- [PHASE3B_BACKFILL_BONUS_EVENTS.sql](../supabase/PHASE3B_BACKFILL_BONUS_EVENTS.sql)  
- [PHASE3C_BONUS_PARITY_CLEANUP.sql](../supabase/PHASE3C_BONUS_PARITY_CLEANUP.sql)

## Phase 3B

Tujuan:
- backfill `sales_bonus_events` dari histori `sales_sell_out`
- menghindari mismatch besar hanya karena ledger baru belum punya data lama

Keputusan teknis:
- sumber backfill memakai `sales_sell_out.estimated_bonus`
- ini dipilih agar parity dengan dashboard lama setinggi mungkin
- bukan untuk menghitung ulang bonus dengan rule baru

## Phase 3C

Tujuan:
- membersihkan parity view dari noise row `period_id is null`
- membuat hasil parity lebih relevan untuk evaluasi transisi

Urutan aman:
1. jalankan Phase 3B
2. jalankan Phase 3C
3. cek ulang parity

