# Supabase SQL Layout

## Active SQL Entry Points

File SQL yang aktif dan relevan untuk hardening database saat ini hanya:

- `PHASE1_CORE_LEDGER_AND_GOVERNANCE.sql`
- `PHASE2_DUAL_WRITE_LEDGER_AND_HISTORY.sql`
- `PHASE3_BONUS_READ_MODEL_AND_PARITY.sql`
- `PHASE3B_BACKFILL_BONUS_EVENTS.sql`
- `PHASE3C_BONUS_PARITY_CLEANUP.sql`
- `PHASE4_CUTOVER_LEGACY_BONUS_RPC.sql`
- `PHASE5_CUTOVER_LEADERBOARD_AND_SATOR_BONUS.sql`
- `PHASE6_LEGACY_BONUS_DEPRECATION_GUARDRAILS.sql`
- `PHASE7_DAILY_TARGET_DASHBOARD.sql`

## Official Migration History

Migration resmi tetap berada di folder:

- `migrations/`

Folder ini tidak dibersihkan karena merupakan chain sejarah schema dan function yang sudah pernah diterapkan.

## Archived Legacy SQL

File SQL root lama yang sifatnya:

- debug
- audit manual
- one-off fix
- test script
- eksperimen lama
- compatibility script yang sudah tidak jadi jalur utama

telah dipindahkan ke:

- `_archive/legacy_root_sql/`

Tujuannya:

- root `supabase/` tetap bersih
- developer tidak bingung memilih file yang harus dijalankan
- jejak historis tetap ada untuk forensic bila diperlukan
