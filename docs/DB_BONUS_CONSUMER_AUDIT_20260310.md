# DB BONUS CONSUMER AUDIT
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** ACTIVE FOLLOW-UP AUDIT

---

## 1. PURPOSE

Dokumen ini mencatat semua consumer bonus yang masih memakai source legacy, agar tidak ada pembacaan bonus yang diam-diam menjadi bom waktu.

Audit ini dibagi menjadi:
- consumer utama yang sudah dicutover
- consumer compatibility yang masih aman sementara
- consumer yang perlu dicutover berikutnya

---

## 2. ALREADY CUT OVER

Sudah diarahkan ke source event-based:

- RPC `get_promotor_bonus_summary(...)`
- RPC `get_promotor_bonus_details(...)`
- [promotor_home_tab.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/tabs/promotor_home_tab.dart)
- [promotor_profil_tab.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/tabs/promotor_profil_tab.dart)
- [bonus_detail_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/bonus_detail_page.dart)
  - aman karena memakai RPC compatibility yang sudah dicutover ke ledger

---

## 3. STILL USING LEGACY FIELDS

### 3.1 Frontend Direct Reads

Masih ada pembacaan langsung ke `estimated_bonus` di:

- [stok_toko_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stok_toko_page.dart)
- [sator_sales_tab.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/tabs/sator_sales_tab.dart)

Status:
- `SAFE AS COMPATIBILITY`

Alasan:
- parity bonus sudah `MATCH`
- `estimated_bonus` masih konsisten dengan ledger untuk histori yang sudah dibackfill
- pembacaan ini tidak lagi menjadi sumber bonus utama promotor

### 3.2 SQL / RPC Legacy Bonus Aggregation

Masih ada banyak function/script yang memakai:
- `sales_sell_out.estimated_bonus`
- `dashboard_performance_metrics.estimated_bonus_total`

Contoh kategori:
- leaderboard
- SATOR team detail
- audit / debug SQL lama
- reporting helper lama

Status:
- `NEEDS CONTROLLED CLEANUP`

---

## 4. RISK CLASSIFICATION

### 4.1 Low Risk For Now

Masih boleh hidup sementara:
- direct display bonus per transaksi
- audit SQL historis
- debug scripts
- compatibility fields selama parity tetap tersedia

### 4.2 Medium Risk

Perlu migrasi bertahap:
- leaderboard yang menjumlah `estimated_bonus`
- SATOR/team pages yang memakai agregasi bonus legacy
- fungsi summary lintas user yang belum membaca `sales_bonus_events`

### 4.3 High Risk

Saat ini sudah ditutup:
- bonus promotor utama di home/profile/detail memakai source lama sebagai sumber final

---

## 5. RECOMMENDED NEXT CUTOVER ORDER

Urutan aman berikutnya:

1. leaderboard functions
2. SATOR team bonus/detail functions
3. page-level direct reads yang masih ambil `estimated_bonus`
4. cleanup audit/debug SQL lama bila memang masih dipakai operasional

---

## 6. FINAL CONCLUSION

Setelah Phase 4:
- jalur bonus promotor utama sudah aman
- sisa consumer legacy tidak lagi tergolong bom waktu kritis
- tetapi masih perlu cleanup bertahap agar arsitektur benar-benar konsisten end-to-end

