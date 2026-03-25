# DB MIGRATION ROADMAP FINAL
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** ACTIVE EXECUTION ROADMAP

---

## 1. PURPOSE

Dokumen ini menerjemahkan blueprint final dan gap analysis menjadi roadmap migrasi database yang aman untuk database existing.

Tujuan:
- menutup gap arsitektur tanpa rewrite brutal
- menjaga backward compatibility
- memastikan perubahan dilakukan bertahap dan bisa diverifikasi

Dokumen acuan:
- [DB_SCHEMA_GAP_ANALYSIS_20260310.md](./DB_SCHEMA_GAP_ANALYSIS_20260310.md)
- [DB_SCHEMA_BLUEPRINT_FINAL.md](./DB_SCHEMA_BLUEPRINT_FINAL.md)
- [DB_INDEXING_BLUEPRINT.md](./DB_INDEXING_BLUEPRINT.md)
- [DB_RLS_BLUEPRINT.md](./DB_RLS_BLUEPRINT.md)

---

## 2. STRATEGY

Strategi yang dipakai:
- tambah object baru dulu
- jangan langsung ubah object lama yang masih dipakai app
- sinkronkan write path bertahap
- pindahkan read path setelah parity angka lolos
- deprecated object lama hanya setelah aman

Prinsip:
- additive first
- compatibility preserved
- parity verified
- cleanup last

---

## 3. PHASE OVERVIEW

### Phase 0: Freeze Architecture

Status:
- selesai

Artefak:
- standar database
- schema blueprint
- indexing blueprint
- RLS blueprint
- gap analysis

### Phase 1: Add Missing Core Ledger Tables

Fokus:
- menambah tabel yang dibutuhkan tanpa mengganggu flow lama

Target object:
- `sales_bonus_events`
- `sales_sell_out_status_history`
- `sell_in_order_status_history`
- `stock_chip_request_history`
- governance tables:
  - `error_logs`
  - `job_runs`
  - `idempotency_keys`
  - `rule_snapshots`
  - `recalc_requests`

Status:
- prioritas tertinggi

### Phase 2: Dual-Write and History Capture

Fokus:
- function/trigger existing menulis ke tabel baru

Contoh:
- `process_sell_out_atomic(...)`
  - tetap insert ke `sales_sell_out`
  - tambah insert ke `sales_sell_out_status_history`
  - tambah insert ke `sales_bonus_events`

- `finalize_sell_in_order(...)`
  - tetap insert ke `sell_in_orders`, `sell_in_order_items`, `sales_sell_in`
  - tambah insert ke `sell_in_order_status_history`

- chip approval flow
  - tambah insert ke `stock_chip_request_history`

### Phase 3: Read Model Refactor

Fokus:
- ubah dashboard/reporting agar membaca dari source yang lebih benar

Contoh:
- bonus dashboard membaca dari summary bonus berbasis `sales_bonus_events`
- sell-in reporting membaca dari `sell_in_orders` finalized model
- status timelines membaca dari history tables

### Phase 4: Governance and RLS Tightening

Fokus:
- tambah policy dan guardrail untuk object baru
- lock governance layer
- least privilege enforcement

### Phase 5: Cleanup and Deprecation

Fokus:
- beri label deprecated untuk object compatibility
- block write baru ke object lama yang sudah digantikan
- drop hanya jika seluruh flow dan reporting sudah aman

---

## 4. PHASE 1 DETAIL

### 4.1 `sales_bonus_events`

Tujuan:
- menjadikan bonus event-based dan audit-ready

Minimal kolom:
- `id`
- `sales_sell_out_id`
- `user_id`
- `period_id`
- `bonus_type`
- `rule_id`
- `rule_snapshot`
- `bonus_amount`
- `is_projection`
- `calculation_version`
- `created_at`
- `created_by`

Catatan:
- belum perlu langsung menghapus `estimated_bonus`
- `estimated_bonus` tetap dipertahankan sementara untuk compatibility

### 4.2 `sales_sell_out_status_history`

Tujuan:
- jejak perubahan status penjualan

Minimal kolom:
- `id`
- `sales_sell_out_id`
- `old_status`
- `new_status`
- `changed_at`
- `changed_by`
- `notes`

### 4.3 `sell_in_order_status_history`

Tujuan:
- jejak perubahan order status

Minimal kolom:
- `id`
- `order_id`
- `old_status`
- `new_status`
- `changed_at`
- `changed_by`
- `notes`

### 4.4 `stock_chip_request_history`

Tujuan:
- jejak perubahan request chip

Minimal kolom:
- `id`
- `stock_chip_request_id`
- `old_status`
- `new_status`
- `changed_at`
- `changed_by`
- `notes`

### 4.5 Governance Tables

#### `error_logs`

Untuk:
- log workflow gagal
- debug operasional

#### `job_runs`

Untuk:
- refresh summary
- recalculation
- nightly job

#### `idempotency_keys`

Untuk:
- anti double submit
- anti duplicate processing

#### `rule_snapshots`

Untuk:
- simpan snapshot rule jika perlu reuse lintas event

#### `recalc_requests`

Untuk:
- audit proses recalculation bonus/summary

---

## 5. PHASE 2 DETAIL

### 5.1 Sell Out Write Path

Object utama:
- `process_sell_out_atomic(...)`

Perubahan:
- insert row history awal `pending/verified`
- insert row `sales_bonus_events`
- jika chip sale atau exclusion tertentu berlaku, event bonus harus eksplisit `0` atau type khusus, bukan diam-diam hilang

### 5.2 Sell In Write Path

Object utama:
- `finalize_sell_in_order(...)`

Perubahan:
- insert history status `pending -> finalized`
- jika nanti ada approval path tambahan, history tetap siap

### 5.3 Chip Request Write Path

Object utama:
- submit / approve / reject chip request functions

Perubahan:
- setiap perubahan status chip request menulis ke history

---

## 6. PHASE 3 DETAIL

### 6.1 Bonus Reporting Migration

Urutan:
1. buat summary/view berbasis `sales_bonus_events`
2. bandingkan hasilnya dengan `dashboard_performance_metrics.estimated_bonus_total`
3. jika parity konsisten, dashboard dipindah

### 6.2 Sell In Reporting Migration

Urutan:
1. summary sell-in berbasis `sell_in_orders`
2. `sales_sell_in` tetap dipertahankan sementara
3. setelah parity aman, `sales_sell_in` diposisikan compatibility-only

### 6.3 Status Timeline UI

UI status sebaiknya nanti baca dari history table baru, bukan hanya field status current.

---

## 7. PHASE 4 DETAIL

### 7.1 RLS For New Tables

Wajib ditambahkan:
- `sales_bonus_events`
- `sales_sell_out_status_history`
- `sell_in_order_status_history`
- `stock_chip_request_history`
- governance tables

### 7.2 Lock Governance Tables

Policy:
- admin/service only

### 7.3 Restrict Direct Writes

Untuk object sensitif:
- insert/update hanya lewat RPC/function/service path

---

## 8. PHASE 5 DETAIL

Object yang kemungkinan menjadi compatibility layer:
- `sales_sell_in`
- kolom `estimated_bonus` di `sales_sell_out`
- object summary lama tertentu

Aturan cleanup:
- jangan drop sampai parity terbukti
- beri deprecation note
- block write baru hanya setelah pengganti aktif penuh

---

## 9. EXECUTION ORDER

Urutan kerja yang direkomendasikan:

1. migration tahap 1: core ledger + governance tables
2. migration tahap 2: trigger/function dual-write
3. verification SQL untuk parity dan integrity
4. migration tahap 3: summary/view baru
5. migration tahap 4: RLS tightening
6. migration tahap 5: deprecation cleanup

---

## 10. SUCCESS CRITERIA

Roadmap dianggap berhasil bila:
- bonus bisa ditrace ke event detail
- sell out punya history status
- sell in punya history status
- chip request punya history status
- governance layer formal tersedia
- dashboard bisa direkonsiliasi dengan source baru
- tidak ada flow existing yang rusak

---

## 11. IMMEDIATE NEXT STEP

Langkah teknis berikutnya:
- buat `draft SQL migration tahap 1`

Isi tahap 1:
- create missing ledger tables
- create governance tables
- add indexes dasar
- enable RLS baseline untuk object baru

