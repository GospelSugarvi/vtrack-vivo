# DB SCHEMA GAP ANALYSIS
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** ACTIVE WORKING DOCUMENT

---

## 1. PURPOSE

Dokumen ini membandingkan:
- blueprint final yang baru dikunci
- struktur database/migration yang saat ini sudah ada

Tujuannya:
- mengetahui apa yang sudah sesuai
- mengetahui apa yang belum ada
- mengetahui object legacy apa yang harus dipertahankan sementara
- menentukan migrasi bertahap yang aman

Dokumen acuan:
- [DATABASE_ARCHITECTURE_STANDARD.md](./DATABASE_ARCHITECTURE_STANDARD.md)
- [DB_SCHEMA_BLUEPRINT_FINAL.md](./DB_SCHEMA_BLUEPRINT_FINAL.md)
- [DB_INDEXING_BLUEPRINT.md](./DB_INDEXING_BLUEPRINT.md)
- [DB_RLS_BLUEPRINT.md](./DB_RLS_BLUEPRINT.md)

---

## 2. EXECUTIVE SUMMARY

Kondisi saat ini:
- fondasi master schema utama sudah ada
- beberapa domain transaksi besar sudah berjalan
- model `sell in` sudah mulai bergerak ke header-detail yang benar
- model `stok` dan `sell out` masih memakai naming/struktur hybrid lama
- model `bonus` masih terlalu dekat ke kolom kalkulasi/aggregate, belum bersih event-based
- governance layer belum lengkap sebagai paket resmi

Kesimpulan:
- database existing bisa dipakai sebagai basis
- tetapi belum sepenuhnya sesuai standar final
- perlu migrasi bertahap, bukan rewrite kasar

---

## 3. SOURCE REVIEWED

Sumber yang ditinjau:
- `supabase/migrations/20260115_init_schema.sql`
- `supabase/migrations/20260303_sellin_finalization_mvp.sql`
- `supabase/migrations/20260304_sellout_atomic_process.sql`
- `supabase/migrations/20260309_stock_chip_relocation_flow.sql`
- handover DB hardening dan catatan migration lain yang relevan

---

## 4. GAP ANALYSIS BY DOMAIN

### 4.1 Master Data

#### Existing

Sudah ada:
- `users`
- `stores`
- `products`
- `product_variants`
- `target_periods`
- `user_targets`
- hierarchy tables dasar
- `assignments_promotor_store`

#### Gap

Belum terlihat sebagai standar resmi yang konsisten:
- `assignments_sator_store`
- pemisahan target detail ke tabel turunan
- pemisahan bonus rule ke tabel yang lebih eksplisit (`flat`, `ratio`, `range`) jika memang belum final di DB existing

#### Status

`PARTIALLY ALIGNED`

#### Action

- pertahankan tabel existing
- rapikan naming dan constraint
- tambah tabel assignment/target detail yang masih kurang

---

### 4.2 Sell Out

#### Existing

Sudah ada:
- `sales_sell_out`
- proses atomic via `process_sell_out_atomic(...)`
- relasi ke stok existing melalui `stok_id`
- penambahan field chip sale

#### Gap

Belum terlihat sebagai model final yang lengkap:
- `sales_sell_out_status_history`
- `sales_bonus_events` sebagai source of truth bonus event
- pemisahan tegas antara transaksi penjualan dan hasil bonus
- naming stok masih bergantung ke tabel legacy-style `stok`

#### Status

`PARTIALLY ALIGNED`

#### Action

- jangan rewrite `sales_sell_out`
- tambahkan status history
- tambahkan bonus event table
- transisikan perhitungan bonus ke event-based model

---

### 4.3 Sell In

#### Existing

Sudah ada:
- `sales_sell_in` model lama untuk feed/reporting
- `sell_in_orders`
- `sell_in_order_items`
- workflow `finalize_sell_in_order(...)`

Ini sudah bergerak ke arsitektur yang benar.

#### Gap

Belum lengkap:
- status history resmi (`sales_sell_in_status_history` atau `sell_in_order_status_history`)
- naming belum sinkron dengan blueprint final
- masih ada backward compatibility insert ke `sales_sell_in`

#### Status

`MOSTLY ALIGNED`

#### Action

- pertahankan `sell_in_orders` + `sell_in_order_items`
- tambah status history
- definisikan `sales_sell_in` sebagai compatibility/legacy reporting feed sampai summary baru siap

---

### 4.4 Stock

#### Existing

Sudah ada:
- tabel `stok`
- `stock_movement_log`
- chip request workflow (`stock_chip_requests`)
- relocation flow

Secara fungsi operasional, domain stok sudah lumayan kaya.

#### Gap

Masalah utama:
- naming tidak sesuai blueprint final
- source of truth masih tersebar antara `stok`, `stock_movement_log`, dan beberapa field state pada row stok
- belum rapi dipresentasikan sebagai:
  - `stock_items`
  - `stock_movements`
  - `chip_requests`
  - `chip_request_history`

#### Status

`FUNCTIONALLY PRESENT, STRUCTURALLY HYBRID`

#### Action

- jangan drop `stok` sekarang
- treat `stok` sebagai existing `stock_items`
- treat `stock_movement_log` sebagai existing `stock_movements`
- pertimbangkan rename konseptual dulu di dokumentasi, rename fisik belakangan jika benar-benar perlu
- tambah history table untuk chip request bila belum ada

---

### 4.5 Bonus

#### Existing

Sudah ada:
- bonus rule infrastructure
- trigger/function bonus logic
- kolom bonus/estimated bonus di beberapa tempat
- dashboard aggregate bonus

#### Gap

Belum sesuai standar final:
- belum ada `sales_bonus_events` sebagai ledger bonus event yang jelas
- bonus masih terlalu dekat dengan trigger langsung ke summary
- belum terlihat rule snapshot formal per event bonus

#### Status

`NOT FULLY ALIGNED`

#### Action

- domain bonus harus jadi fokus redesign bertahap
- tambah `sales_bonus_events`
- pertahankan summary existing sementara
- migrasikan dashboard agar akhirnya membaca dari bonus event summary

---

### 4.6 Activity

#### Existing

Sudah ada:
- `activity_logs`
- sejumlah fitur activity lain dari migration Januari-Februari

#### Gap

Belum jelas pemetaan final antara:
- general event log
- tabel spesifik seperti promotion/follower/vast jika ada

Tetapi pondasinya sudah benar: event-based.

#### Status

`MOSTLY ALIGNED`

#### Action

- pertahankan `activity_logs`
- audit tabel aktivitas spesifik yang sudah ada
- finalkan mana yang tetap general log dan mana yang harus tabel domain terpisah

---

### 4.7 AllBrand

#### Existing

Ada indikasi allbrand system sudah ada dari migration Maret 2026.

#### Gap

Belum dipastikan apakah struktur existing sudah:
- header-detail
- traceable per item
- mudah diquery

#### Status

`NEEDS VERIFICATION`

#### Action

- audit object allbrand existing
- samakan ke model `allbrand_reports` + `allbrand_report_items` bila belum sesuai

---

### 4.8 Warehouse Daily Reference

#### Existing

Sudah ada indikasi:
- `warehouse_stock_daily`
- `warehouse_stock`
- object legacy `stok_gudang_harian`
- safeguard legacy sudah disiapkan

#### Gap

Yang perlu ditegaskan:
- mana object aktif
- mana object compatibility
- mana object deprecated

#### Status

`PARTIALLY ALIGNED`

#### Action

- lock `warehouse_stock_daily` sebagai snapshot reference aktif
- pertahankan legacy dengan safeguard
- dokumentasikan object aktif vs deprecated secara resmi

---

### 4.9 Governance Layer

#### Existing

Sudah ada:
- `audit_logs`
- sebagian guardrail audit SQL
- hardening RLS awal

#### Gap

Belum terlihat lengkap sebagai layer resmi:
- `error_logs`
- `job_runs`
- `idempotency_keys`
- `rule_snapshots`
- `recalc_requests`

#### Status

`PARTIALLY ALIGNED`

#### Action

- tambahkan governance tables tahap khusus
- jadikan ini bagian migration resmi, bukan utility script lepas

---

## 5. NAMING ALIGNMENT

Beberapa object existing secara konsep sudah benar tetapi namanya belum selaras dengan blueprint.

### Existing -> Blueprint Concept

- `stok` -> setara konsep `stock_items`
- `stock_movement_log` -> setara konsep `stock_movements`
- `stock_chip_requests` -> setara konsep `chip_requests`
- `sell_in_orders` -> setara konsep `sales_sell_in_orders`
- `sell_in_order_items` -> setara konsep `sales_sell_in_order_items`

Keputusan:
- untuk saat ini prioritaskan alignment konseptual dulu
- rename fisik tabel hanya dilakukan jika manfaatnya lebih besar dari risiko backward compatibility

---

## 6. LEGACY / COMPATIBILITY OBJECTS

Object yang harus dianggap compatibility layer sementara:
- `sales_sell_in`
- `stok_gudang_harian`
- kemungkinan beberapa aggregate dashboard lama

Aturan:
- jangan jadi dasar fitur baru
- pertahankan sementara untuk compatibility/reporting lama
- siapkan deprecation path resmi

---

## 7. PRIORITY GAPS TO CLOSE

Prioritas tertinggi:

1. bonus event ledger
2. sell out status history
3. sell in status history
4. governance tables
5. allbrand structure verification
6. target detail tables normalization

Prioritas menengah:

1. helper tables untuk assignment scope yang masih kurang
2. summary rebuild strategy
3. partial index completion

Prioritas rendah:

1. rename fisik tabel hybrid lama
2. cosmetic cleanup naming jika compatibility risk masih tinggi

---

## 8. SAFE MIGRATION STRATEGY

Strategi aman yang direkomendasikan:

### Phase 1

- tambah tabel yang belum ada tanpa mengganggu tabel existing
- tambah status history tables
- tambah governance tables
- tambah bonus event table

### Phase 2

- ubah function/trigger agar menulis ke tabel baru juga
- tetap pertahankan output lama untuk backward compatibility

### Phase 3

- pindahkan dashboard/read models ke source baru
- verifikasi parity angka

### Phase 4

- deprecated object lama
- block write ke object legacy
- drop hanya setelah aman

---

## 9. FINAL CONCLUSION

Database existing tidak perlu dibuang.

Yang perlu dilakukan adalah:
- rapikan arsitektur
- tutup gap pada domain sensitif
- migrasikan pelan tapi disiplin

Keputusan inti:
- pakai DB existing sebagai fondasi
- jangan rewrite brutal
- lakukan hardening dan alignment bertahap sampai sesuai blueprint final

