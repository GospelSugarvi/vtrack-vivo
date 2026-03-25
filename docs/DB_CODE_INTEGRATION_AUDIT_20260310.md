# DB Code Integration Audit - 2026-03-10

## Scope

Audit ini memeriksa integrasi antara Flutter code dan database aktif setelah Phase 1-6 selesai.

Fokus audit:

- pemanggilan `rpc(...)`
- pembacaan langsung `from(...)`
- kecocokan dengan source of truth yang sudah ditetapkan

## Kesimpulan Utama

Status umum:

- fondasi database yang dimigrasikan sudah terkoneksi dengan kode aktif
- jalur bonus aktif sudah sinkron ke source baru
- jalur sell-in aktif sudah sinkron ke model baru
- masih ada beberapa read path legacy di luar area bonus yang belum dicutover, tetapi bukan bom waktu kritis

## Area Yang Sudah Sinkron

### 1. Bonus

Source of truth:

- `sales_bonus_events`

Status:

- bonus promotor utama sudah baca via RPC yang sudah dicutover ke event ledger
- leaderboard promotor sudah event-based
- live feed promotor sudah event-based
- leaderboard SATOR sudah event-based
- team live feed SATOR sudah event-based
- detail tim SATOR sudah event-based
- runtime Flutter tidak lagi membaca `estimated_bonus` atau `estimated_bonus_total`

## 2. Sell-Out

Source of truth:

- `sales_sell_out`

Status:

- flow transaksi aktif sudah lewat `process_sell_out_atomic(...)`
- function itu sudah dual-write ke:
  - `sales_sell_out_status_history`
  - `sales_bonus_events`
- kode Flutter `sell_out_page.dart` menggunakan RPC proses atomik, bukan rangkaian write manual

## 3. Sell-In

Source of truth:

- `sell_in_orders`
- `sell_in_order_items`

Compatibility:

- `sales_sell_in` masih dipertahankan sebagai feed kompatibilitas

Status:

- dashboard sell-in SATOR memakai RPC:
  - `get_sator_sellin_summary`
  - `get_pending_orders`
- finalisasi sell-in memakai:
  - `finalize_sell_in_order_by_id`
- achievement sell-in membaca `sell_in_orders`
- riwayat finalisasi sell-in membaca `sell_in_orders`

Kesimpulan:

- jalur sell-in aktif di app sudah mengikuti model baru
- `sales_sell_in` tidak ditemukan sebagai read path aktif di Flutter untuk fitur sell-in utama

## 4. Chip Request

Source of truth:

- `stock_chip_requests`

History:

- `stock_chip_request_history`

Status:

- submit chip request dan review request sudah memakai RPC aktif
- history chip request ditulis dari function database
- UI monitoring chip masih membaca tabel transaksi utama untuk tampilan, tetapi tidak lagi bergantung ke bonus legacy

## 5. Governance / History Tables

Tables:

- `sales_sell_out_status_history`
- `sell_in_order_status_history`
- `stock_chip_request_history`
- `error_logs`
- `job_runs`
- `idempotency_keys`
- `rule_snapshots`
- `recalc_requests`

Status:

- sudah aktif di database
- belum semuanya punya consumer UI langsung, dan itu normal
- fungsinya sebagai audit / governance layer, bukan primary page datasource

## Temuan Legacy Yang Masih Ada

### 1. `dashboard_performance_metrics`

Masih dibaca di:

- `lib/features/sator/presentation/pages/visiting/pre_visit_page.dart`

Pemakaian saat ini:

- pembacaan histori performa omzet/unit/fokus per period untuk kebutuhan monitoring kunjungan

Status risiko:

- bukan bom waktu bonus
- bukan conflict dengan bonus source of truth baru
- masih termasuk read-model lama yang belum dipotong total

Rekomendasi:

- boleh dipertahankan sementara
- jika nanti modul visiting ikut di-hardening, pindahkan ke read-model baru yang lebih eksplisit

### 2. SQL migration history lama

Masih ada di:

- `supabase/migrations/`
- `supabase/_archive/legacy_root_sql/`

Status:

- ini bukan runtime app
- ini jejak historis
- tidak perlu dicutover, hanya perlu disiplin penggunaan

## Verifikasi Yang Sudah Dilakukan

- audit `rpc(...)` di folder `lib/`
- audit `from(...)` di folder `lib/`
- verifikasi runtime bonus aktif tidak lagi membaca `estimated_bonus`
- verifikasi sell-in aktif memakai `sell_in_orders` / RPC baru
- verifikasi root `supabase/` hanya menyisakan phase SQL aktif

## Putusan Akhir

Yang bisa diklaim selesai:

- database bonus hardening selesai
- code integration bonus selesai
- code integration sell-in aktif selesai
- history/governance integration selesai pada jalur write yang dimigrasikan

Yang belum diklaim selesai total:

- seluruh modul app di luar scope bonus/sell-in/history belum diaudit untuk redesign penuh
- beberapa read model lama seperti `dashboard_performance_metrics` masih dipakai pada modul tertentu

## Final Status

Untuk area yang dikerjakan dalam rangka hardening database:

- `PASS`

Untuk seluruh aplikasi lintas semua modul:

- `MOSTLY SYNCHRONIZED, WITH CONTROLLED LEGACY READ PATHS`
