# HANDOVER DATABASE HARDENING - 03 Mar 2026

## Ringkasan
Fokus sesi:
1. Menyambungkan MCP Supabase agar audit dan perubahan DB bisa dieksekusi langsung (tanpa copy-paste manual panjang).
2. Audit sinkronisasi Frontend <-> Backend (tabel + RPC yang dipakai di `lib/`).
3. Perbaikan konsistensi modul Sell In `Stok Gudang`.
4. Hardening database tahap 1 (RLS + policy baseline non-breaking).

Hasil utama:
- MCP Supabase berhasil aktif dan dipakai untuk eksekusi SQL live.
- Audit sinkronisasi berhasil:
  - `51` tabel dipakai frontend.
  - `45` RPC dipakai frontend.
  - Missing RPC: `0`.
- Perbaikan stok gudang diterapkan di DB + app.
- Hardening RLS tahap 1 diterapkan sukses ke 9 tabel risiko.

---

## 1) Perbaikan Sell In - Stok Gudang

### A. Perbaikan di aplikasi Flutter
File:
- `lib/features/sator/presentation/pages/sell_in/stok_gudang_page.dart`

Perubahan:
- RPC `get_stok_gudang_status_for_date` sekarang mengirim `p_sator_id` eksplisit (selain `p_tanggal`) agar konteks user konsisten dengan `get_gudang_stock`.

Validasi:
```bash
/home/geger/flutter/bin/flutter analyze lib/features/sator/presentation/pages/sell_in/stok_gudang_page.dart
# No issues found!
```

### B. Perbaikan di database
Diterapkan via MCP Supabase:
- Tambah signature baru:
  - `get_stok_gudang_status_for_date(p_tanggal date, p_sator_id uuid default null)`
- Signature lama tetap dipertahankan (backward compatible):
  - `get_stok_gudang_status_for_date(p_tanggal date)` -> delegasi ke signature baru.

Tujuan:
- Hilangkan mismatch konteks user antara:
  - fungsi yang membaca berdasarkan `auth.uid()`
  - fungsi yang membaca berdasarkan `p_sator_id`.

---

## 2) Hasil Audit Sinkronisasi FE-BE

### Cakupan audit
- Ekstraksi semua `.from('...')` dan `.rpc('...')` dari folder `lib/`.
- Cross-check ke object yang benar-benar ada di DB.

### Temuan inti
1. Total referensi frontend:
   - Tabel: `51`
   - RPC: `45`
2. Missing object:
   - Missing table: `photos` (normal, ini bucket Storage, bukan tabel SQL)
   - Missing RPC: `0`
3. Primary key:
   - Tabel yang dipakai frontend tanpa PK: `0`

---

## 3) Hardening Database Tahap 1 (Sudah Diterapkan)

Migration file:
- `supabase/migrations/20260303_rls_hardening_phase1.sql`

### Ruang lingkup tabel
1. `chat_members`
2. `chat_rooms`
3. `message_reactions`
4. `kpi_ma_scores`
5. `products`
6. `product_variants`
7. `store_groups`
8. `target_periods`
9. `user_targets`

### Yang dilakukan
1. Enable RLS untuk 9 tabel di atas.
2. Tambah helper function role-check:
   - `current_user_role()`
   - `is_admin_user()`
   - `is_admin_or_manager_user()`
   - `is_elevated_user()`
3. Rapikan policy baseline agar aman tapi tetap non-breaking untuk flow saat ini.

### Verifikasi pasca-apply
Status:
- Apply migration: `PASS` (`success: true`)
- RLS 9 tabel: `PASS` (semua `true`)
- Policy count per tabel: `PASS` (kebaca normal)
- Missing RPC frontend: `PASS` (`0`)

---

## 4) Catatan Risiko yang Masih Perlu Lanjutan

1. Masih ada object/tabel legacy yang hidup berdampingan (contoh historis stok gudang), perlu fase cleanup terkontrol.
2. Policy saat ini baseline aman; tahap berikutnya perlu least-privilege lebih ketat per role + per fitur.
3. Perlu regression test per menu (Admin, SATOR, Promotor) setelah hardening agar tidak ada side effect role-based access.

---

## 5) Rekomendasi Lanjutan (Phase 2)

1. Policy tightening per role dan per operasi (`SELECT/INSERT/UPDATE/DELETE`) untuk modul non-chat dan reporting.
2. Cleanup schema legacy/deprecated (arsip + deprecate note + rencana drop bertahap).
3. Tambah audit query pack standar:
   - missing table/RPC check
   - RLS coverage check
   - privilege drift check
4. Buat dokumen mapping resmi FE endpoint -> DB object (single source of truth).

---

## 6) Update Phase 2 yang Sudah Dikerjakan

1. Verifikasi lanjutan setelah hardening:
   - Tabel frontend dengan `RLS OFF` pada schema `public`: `0`.
2. Ditambahkan guardrail audit SQL siap pakai:
   - `supabase/queries/20260303_db_guardrail_audit.sql`
3. Fungsi guardrail ini mencakup:
   - Summary jumlah object FE (tabel + RPC).
   - Deteksi tabel frontend yang hilang di DB.
   - Deteksi tabel frontend dengan RLS OFF.
   - Deteksi tabel frontend yang policy count = 0.
   - Deteksi RPC frontend yang hilang.
   - Deteksi RPC tanpa grant EXECUTE untuk `authenticated`.

Tujuan:
- Mencegah regresi sinkronisasi FE-BE.
- Menjaga standar keamanan database tetap konsisten setelah perubahan fitur.

---

## 7) Status Terkini (03 Mar 2026 malam)

Update operasional terakhir:
1. Koneksi MCP Supabase sudah stabil dan bisa dipakai eksekusi SQL langsung dari terminal `codex` (tanpa copy-paste panjang).
2. Verifikasi stok gudang terbaru sudah mengarah ke tabel aktif `warehouse_stock_daily` dan `warehouse_stock`.
3. Tabel legacy `stok_gudang_harian` terdeteksi masih ada (historical), tetapi bukan sumber data utama fitur Sell In saat ini.

Checklist status:
- FE -> DB object sync: `PASS`
- Missing RPC frontend: `0`
- Frontend table dengan RLS OFF: `0`
- Guardrail audit SQL: `READY`

Rencana lanjutan (Phase 3 - Safe Cleanup):
1. Tambahkan deprecation note resmi untuk object legacy stok gudang.
2. Tambahkan safeguard agar write baru tidak masuk ke tabel legacy.
3. Lanjutkan tightening policy least-privilege per role per fitur.

---

## 8) Artefak Phase 3 (Sudah Disiapkan)

File migration baru:
- `supabase/migrations/20260303_stok_gudang_legacy_safeguard.sql`

Isi migration:
1. Memberi `COMMENT` deprecation di tabel `public.stok_gudang_harian`.
2. `REVOKE INSERT/UPDATE/DELETE` dari role `anon` dan `authenticated`.
3. Menambahkan trigger `trg_block_legacy_stok_gudang_harian_writes` untuk memblok write ke tabel legacy.

File verifikasi baru:
- `supabase/queries/20260303_verify_stok_gudang_legacy_safeguard.sql`

Cakupan verifikasi:
1. Cek comment deprecation pada tabel legacy.
2. Cek trigger safeguard aktif.
3. Cek matrix privilege `anon/authenticated` untuk `SELECT/INSERT/UPDATE/DELETE`.

Catatan eksekusi:
- Attempt apply migration langsung via `codex exec` + MCP sudah dicoba, namun sesi CLI hang (tidak mengembalikan output).
- SQL migration dan query verifikasi sudah siap 100% untuk dijalankan ulang di sesi MCP Anda yang aktif.
