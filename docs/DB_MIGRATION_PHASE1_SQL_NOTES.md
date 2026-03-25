# DB MIGRATION PHASE 1 SQL NOTES
**Date:** 10 March 2026  
**SQL Draft:** [supabase/PHASE1_CORE_LEDGER_AND_GOVERNANCE.sql](../supabase/PHASE1_CORE_LEDGER_AND_GOVERNANCE.sql)

Tujuan draft ini:
- menambah ledger bonus event
- menambah history tables
- menambah governance tables
- menambah baseline indexes
- menambah baseline RLS untuk object baru

Catatan:
- file ini masih draft review-safe
- belum dimasukkan ke rantai migration versioned resmi
- aman untuk direview dulu sebelum dijadikan migration final bernomor tanggal

Sebelum apply ke DB live, yang perlu diverifikasi:
- apakah `public.is_admin_user()` dan `public.is_elevated_user()` sudah ada
- apakah naming policy untuk table baru ingin langsung final atau mengikuti konvensi team
- apakah `bonus_type` enum/check list perlu ditambah varian lain
- apakah governance table tetap admin-only semua, atau ada beberapa yang service-role only

