# DB MIGRATION PHASE 2 SQL NOTES
**Date:** 10 March 2026  
**SQL Draft:** [supabase/PHASE2_DUAL_WRITE_LEDGER_AND_HISTORY.sql](../supabase/PHASE2_DUAL_WRITE_LEDGER_AND_HISTORY.sql)

Tujuan draft ini:
- membuat write path existing mulai mengisi ledger/history baru
- menjaga flow lama tetap hidup
- belum memindahkan dashboard/reporting ke source baru

Cakupan draft:
- `process_sell_out_atomic(...)`
- `finalize_sell_in_order(...)`
- `submit_chip_request(...)`
- `review_chip_request(...)`

Catatan penting:
- draft ini sudah mencakup flow chip request `fresh_to_chip` dan `sold_to_chip`
- `review_chip_request(...)` sudah digabung dengan logika reopen sold stock dan history insert
- untuk bonus, draft ini masih menulis event ledger dari sumber legacy yang tersedia saat ini
- kalkulasi bonus final yang sepenuhnya rule-based masih perlu fase berikutnya

Sebelum apply ke DB live:
- verifikasi juga apakah ada trigger bonus existing yang perlu dibiarkan berjalan berdampingan sementara
