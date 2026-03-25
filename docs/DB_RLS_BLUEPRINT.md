# DB RLS BLUEPRINT
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** ACTIVE BLUEPRINT

---

## 1. PURPOSE

Dokumen ini menetapkan baseline Row Level Security (RLS) final untuk sistem.

Tujuan:
- memastikan akses data dijaga di database
- mencegah kebocoran data lintas role
- menjadi acuan implementasi policy Supabase/PostgreSQL

Dokumen ini melengkapi:
- [DATABASE_ARCHITECTURE_STANDARD.md](./DATABASE_ARCHITECTURE_STANDARD.md)
- [DB_SCHEMA_BLUEPRINT_FINAL.md](./DB_SCHEMA_BLUEPRINT_FINAL.md)

---

## 2. SECURITY PRINCIPLES

### 2.1 UI Is Not Security

Menu yang disembunyikan di Flutter bukan proteksi.
Proteksi final wajib di RLS.

### 2.2 Least Privilege

Policy dipisah berdasarkan:
- `SELECT`
- `INSERT`
- `UPDATE`
- `DELETE`

Jangan gunakan policy serba boleh kecuali benar-benar untuk service role/admin terkontrol.

### 2.3 Hierarchy-Based Access

Akses mengikuti assignment resmi.

Aturan inti:
- promotor lihat scope sendiri
- sator lihat promotor dan toko bawahannya
- spv lihat sator dan area bawahannya
- manager/admin lihat scope lebih luas sesuai penugasan

### 2.4 Sensitive Data Segregation

Tidak semua data tim boleh dibuka penuh ke atasan.

Contoh:
- breakdown bonus detail promotor tidak otomatis bisa dilihat sator
- data customer sensitif tidak boleh terbuka ke role yang tidak perlu
- audit log internal tidak boleh dibuka ke semua role

---

## 3. REQUIRED HELPER FUNCTIONS

Sebelum policy detail, sistem perlu helper function yang konsisten.

Minimal:
- `current_user_role()`
- `is_admin_user()`
- `is_manager_user()`
- `is_spv_user()`
- `is_sator_user()`
- `is_promotor_user()`
- `can_access_promotor(p_promotor_id uuid)`
- `can_access_sator(p_sator_id uuid)`
- `can_access_store(p_store_id uuid)`
- `current_user_store_ids()`
- `current_user_promotor_ids()`
- `current_user_sator_ids()`

Aturan:
- helper function harus `stable`
- logic akses tidak disalin ulang berkali-kali di semua policy

---

## 4. ROLE ACCESS MODEL

### 4.1 Promotor

Promotor boleh:
- lihat profil sendiri
- lihat target sendiri
- lihat penjualan sendiri
- lihat bonus sendiri
- lihat aktivitas sendiri
- lihat stok toko penugasannya
- buat transaksi dan input yang memang menjadi tugasnya

Promotor tidak boleh:
- lihat detail promotor lain
- lihat bonus orang lain
- lihat audit log
- lihat data lintas toko di luar assignment

### 4.2 SATOR

SATOR boleh:
- lihat data promotor bawahannya
- lihat data toko dalam assignment-nya
- lihat sell-in, stok, aktivitas, allbrand dalam scope timnya
- approve request yang memang menjadi otoritasnya

SATOR tidak boleh:
- lihat bonus detail pribadi promotor jika itu sensitif payroll
- akses data tim sator lain
- edit master target/admin-only objects

### 4.3 SPV

SPV boleh:
- lihat area tim di bawah sator-sator yang ditugaskan
- lihat ringkasan kinerja dan detail operasional yang memang dibutuhkan

SPV tidak boleh:
- ubah object admin-only
- akses data di luar area/hierarchy resmi

### 4.4 Manager / Admin

Admin boleh:
- full CRUD pada master dan konfigurasi bisnis
- lihat data seluruh scope yang ditugaskan

Jika manager area dibedakan dari admin superuser:
- manager area tetap dibatasi oleh assignment area
- admin global bisa full access

---

## 5. TABLE GROUPING FOR RLS

### 5.1 Group A: Self-Scoped Tables

Tabel:
- `users` (untuk row sendiri, kecuali elevated roles)
- `sales_bonus_events`
- `user_targets`
- `notifications`

Rule dasar:
- user biasa hanya bisa `SELECT` row miliknya
- elevated roles boleh dengan aturan tambahan sesuai kebutuhan

### 5.2 Group B: Team-Scoped Transaction Tables

Tabel:
- `sales_sell_out`
- `sales_sell_out_status_history`
- `sales_sell_in_orders`
- `sales_sell_in_order_items`
- `sales_sell_in_status_history`
- `activity_logs`
- `allbrand_reports`
- `allbrand_report_items`
- `promotion_posts`
- `follower_events`
- `vast_applications`
- `chip_requests`
- `chip_request_history`

Rule dasar:
- promotor: row milik sendiri / toko assignment sendiri
- sator: tim dan toko assignment-nya
- spv: area/tim di bawahnya
- manager/admin: scope lebih tinggi

### 5.3 Group C: Store/Stock Scoped Tables

Tabel:
- `stock_items`
- `stock_movements`
- `warehouse_stock_daily`
- `warehouse_stock_daily_items`

Rule dasar:
- promotor: store assignment sendiri
- sator: stores yang dia pegang
- spv/manager: store scope turunan

### 5.4 Group D: Admin-Controlled Master Tables

Tabel:
- `products`
- `product_variants`
- `bonus_rules_*`
- `target_periods`
- `shift_settings`
- `store_groups`

Rule dasar:
- semua authenticated boleh `SELECT` jika dibutuhkan aplikasi
- hanya admin/elevated role boleh `INSERT/UPDATE/DELETE`

### 5.5 Group E: Governance Tables

Tabel:
- `audit_logs`
- `error_logs`
- `job_runs`
- `idempotency_keys`
- `rule_snapshots`
- `recalc_requests`

Rule dasar:
- tidak dibuka ke role biasa
- hanya admin/service role

---

## 6. POLICY BLUEPRINT BY DOMAIN

### 6.1 `users`

`SELECT`
- user bisa lihat row sendiri
- elevated role bisa lihat row dalam scope hierarchy

`UPDATE`
- user boleh update profil aman tertentu milik sendiri
- role/status/assignment tidak boleh diubah user biasa

`INSERT/DELETE`
- admin/service role only

### 6.2 Hierarchy Tables

`SELECT`
- elevated role sesuai scope
- promotor biasanya tidak perlu akses semua row mentah

`INSERT/UPDATE/DELETE`
- admin only

### 6.3 `sales_sell_out`

`SELECT`
- promotor: own rows
- sator: rows promotor bawahannya / store scope-nya
- spv/manager/admin: sesuai hierarchy

`INSERT`
- promotor pada assignment toko aktifnya
- admin override bila perlu

`UPDATE`
- terbatas
- perubahan status approval idealnya lewat RPC/function, bukan update bebas

`DELETE`
- sebisa mungkin admin only atau disallow

### 6.4 `sales_bonus_events`

`SELECT`
- promotor: own bonus rows
- sator/spv: hanya jika kebijakan bisnis membolehkan
- admin: all

Rekomendasi:
- bonus detail promotor dibatasi keras
- atasan cukup lihat summary performance bila payroll detail sensitif

`INSERT/UPDATE/DELETE`
- service path only

### 6.5 `stock_items` and `stock_movements`

`SELECT`
- berdasarkan store scope

`INSERT`
- melalui workflow resmi stok masuk/transfer

`UPDATE`
- tidak bebas
- perubahan status stok harus lewat function/transaction

`DELETE`
- admin only atau block

### 6.6 `chip_requests`

`SELECT`
- promotor pembuat
- sator approver terkait
- elevated role sesuai scope

`INSERT`
- promotor dalam store assignment-nya

`UPDATE`
- hanya untuk perubahan status oleh approver berwenang / service function

### 6.7 `activity_logs`

`SELECT`
- own / team / hierarchy scope

`INSERT`
- user boleh insert aktivitas sendiri yang valid

`UPDATE/DELETE`
- sebaiknya sangat dibatasi

### 6.8 `warehouse_stock_daily`

`SELECT`
- semua role operasional dalam scope relevan

`INSERT/UPDATE`
- sator/admin sesuai workflow

`DELETE`
- admin only

### 6.9 `products`, `product_variants`, `bonus_rules_*`, `target_periods`

`SELECT`
- authenticated read jika dibutuhkan aplikasi

`INSERT/UPDATE/DELETE`
- admin only

### 6.10 `audit_logs`, `error_logs`, `job_runs`

Semua operasi:
- admin/service role only

---

## 7. RECOMMENDED POLICY STYLE

### 7.1 Prefer Helper-Based Policies

Contoh gaya:
- `using (can_access_promotor(promotor_id))`
- `using (can_access_store(store_id))`

Lebih baik daripada menulis subquery hierarchy berulang di setiap tabel.

### 7.2 Separate Read And Write Policies

Jangan gabung semua operasi ke satu policy jika logiknya berbeda.

### 7.3 Service Role For Sensitive Workflows

Workflow sensitif lebih aman lewat:
- edge function
- RPC security definer yang sangat terkontrol

Bukan lewat `UPDATE` bebas dari client.

---

## 8. NON-NEGOTIABLE RLS RULES

- semua tabel frontend-facing wajib RLS `ON`
- tidak boleh ada tabel operasional penting dengan RLS mati
- bonus detail tidak dibuka lintas user tanpa keputusan bisnis jelas
- audit/error/governance tables tidak boleh dibuka ke role biasa
- status approval sensitif tidak boleh diubah direct update bebas

---

## 9. TESTING REQUIREMENTS

Setiap policy penting harus dites minimal untuk:
- promotor own access
- promotor cross-user denial
- sator team access
- sator non-team denial
- spv area access
- admin full access

Tambahan:
- test insert valid
- test insert out-of-scope denial
- test update restricted field denial

---

## 10. IMPLEMENTATION PRIORITY

Urutan implementasi RLS:

1. helper functions role/scope
2. master tables admin-only write policies
3. self-scoped tables
4. team-scoped transaction tables
5. stock/store-scoped tables
6. governance lockdown
7. policy regression tests

---

## 11. FINAL DECISIONS

Keputusan final RLS:
- akses data harus berbasis hierarchy resmi
- semua write sensitif lewat jalur terkontrol
- policy dibedakan per operation
- governance tables ditutup keras
- helper function wajib dipakai untuk menjaga policy tetap rapi dan konsisten

