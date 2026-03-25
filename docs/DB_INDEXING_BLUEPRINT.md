# DB INDEXING BLUEPRINT
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** ACTIVE BLUEPRINT

---

## 1. PURPOSE

Dokumen ini menetapkan aturan indexing final untuk schema sistem.

Tujuan:
- menjaga query tetap cepat saat data tumbuh
- mencegah full table scan pada query kritis
- memastikan dashboard, reporting, dan hierarchy lookup tetap stabil

Index dibuat berdasarkan pola query yang diperkirakan pasti terjadi pada sistem ini.

---

## 2. INDEXING PRINCIPLES

### 2.1 Mandatory

Wajib index:
- primary key
- business unique key
- foreign key lookup columns yang sering di-join
- tanggal/periode untuk tabel transaksi besar
- status aktif/approved yang sering difilter

### 2.2 Query-Based

Index tidak dibuat karena “mungkin berguna”.
Index harus mengikuti:
- query dashboard
- query role access
- query period reporting
- query stock lookup
- query order/approval

### 2.3 Composite Before Random Single Indexes

Jika query nyata selalu memfilter 2-3 kolom bersama, prioritaskan composite index.

### 2.4 Partial Index For Hot Paths

Partial index dipakai untuk subset data yang sangat sering diakses:
- `active = true`
- `status = 'approved'`
- `deleted_at is null`

### 2.5 Write Cost Awareness

Terlalu banyak index memperlambat insert/update.

Jadi:
- tabel raw besar diberi index secukupnya tapi tepat
- tabel summary diberi index sesuai dimensi laporan

---

## 3. GLOBAL INDEX CATEGORIES

### 3.1 Identity Indexes

Contoh:
- PK pada semua tabel utama
- unique pada `username`
- unique pada `serial_imei`

### 3.2 Access Path Indexes

Contoh:
- relasi hierarchy aktif
- assignment aktif
- store scope per sator

### 3.3 Time-Series Indexes

Contoh:
- `transaction_date`
- `business_date`
- `created_at`
- `period_id`

### 3.4 Status Indexes

Contoh:
- `status`
- `active`
- `is_sold`

---

## 4. MASTER TABLE INDEXES

### 4.1 `users`

Wajib:
- PK `id`
- unique `username`

Tambahan:
- index `(role, status)`
- partial index `(id)` where `status = 'active'` hanya jika memang diperlukan oleh policy/helper query

### 4.2 `stores`

Wajib:
- PK `id`

Tambahan:
- index `(area, status)`
- index `(status)`

### 4.3 Hierarchy Tables

#### `hierarchy_manager_spv`

Wajib:
- index `(manager_id, active)`
- index `(spv_id, active)`

#### `hierarchy_spv_sator`

Wajib:
- index `(spv_id, active)`
- index `(sator_id, active)`

#### `hierarchy_sator_promotor`

Wajib:
- index `(sator_id, active)`
- index `(promotor_id, active)`

#### `assignments_promotor_store`

Wajib:
- unique partial index pada promotor aktif
- index `(store_id, active)`

Ideal:
- unique `(promotor_id)` where `active = true`

#### `assignments_sator_store`

Wajib:
- index `(sator_id, active)`
- index `(store_id, active)`

---

## 5. PRODUCT TABLE INDEXES

### 5.1 `products`

Wajib:
- PK `id`

Tambahan:
- index `(status)`
- index `(is_focus, status)`
- index `(bonus_type, status)`

### 5.2 `product_variants`

Wajib:
- PK `id`
- index `(product_id, active)`

Tambahan:
- index `(srp)`
- unique optional `(product_id, ram_rom, color)` jika bisnis menganggap SKU itu unik

---

## 6. SELL OUT INDEXES

### 6.1 `sales_sell_out`

Ini tabel kritis dan hampir pasti besar.

Wajib:
- PK `id`
- unique `serial_imei`
- index `(promotor_id, transaction_date)`
- index `(store_id, transaction_date)`
- index `(variant_id, transaction_date)`
- index `(status, transaction_date)`
- index `(transaction_date)`

Tambahan yang sangat disarankan:
- partial index `(promotor_id, transaction_date)` where `status = 'approved'`
- partial index `(store_id, transaction_date)` where `status = 'approved'`

Jika query bonus banyak join period:
- index `(promotor_id, created_at)`

### 6.2 `sales_sell_out_status_history`

Wajib:
- PK `id`
- index `(sales_sell_out_id, changed_at desc)`

---

## 7. BONUS INDEXES

### 7.1 `sales_bonus_events`

Wajib:
- PK `id`
- index `(sales_sell_out_id)`
- index `(user_id, period_id)`
- index `(period_id, user_id)`
- index `(created_at)`

Tambahan:
- index `(is_projection, period_id)`
- index `(bonus_type, period_id)`

Jika ada rule audit sering:
- index `(rule_id)`

### 7.2 Bonus Rule Tables

#### `bonus_rules_range`

Wajib:
- PK `id`
- index `(user_type, active)`
- index `(active)`

#### `bonus_rules_flat`

Wajib:
- PK `id`
- index `(product_id, active)`

#### `bonus_rules_ratio`

Wajib:
- PK `id`
- index `(product_id, active)`

---

## 8. SELL IN INDEXES

### 8.1 `sales_sell_in_orders`

Wajib:
- PK `id`
- index `(sator_id, business_date)`
- index `(store_id, business_date)`
- index `(status, business_date)`
- index `(business_date)`

### 8.2 `sales_sell_in_order_items`

Wajib:
- PK `id`
- index `(order_id)`
- index `(variant_id)`

### 8.3 `sales_sell_in_status_history`

Wajib:
- PK `id`
- index `(order_id, changed_at desc)`

---

## 9. STOCK INDEXES

### 9.1 `stock_items`

Wajib:
- PK `id`
- unique `serial_imei`
- index `(current_store_id, current_status)`
- index `(variant_id, current_status)`
- index `(is_sold)`

Tambahan:
- partial index `(current_store_id, variant_id)` where `is_sold = false`
- partial index `(current_store_id, stock_type)` where `is_sold = false`

### 9.2 `stock_movements`

Wajib:
- PK `id`
- index `(stock_item_id, business_date desc)`
- index `(from_store_id, business_date)`
- index `(to_store_id, business_date)`
- index `(movement_type, business_date)`
- index `(business_date)`

Jika audit sale-stock sering dipakai:
- index `(related_sale_id)`

### 9.3 `chip_requests`

Wajib:
- PK `id`
- index `(promotor_id, requested_at)`
- index `(sator_id, requested_at)`
- index `(status, requested_at)`
- index `(stock_item_id)`

### 9.4 `warehouse_stock_daily`

Wajib:
- PK `id`
- index `(business_date, created_by)`

### 9.5 `warehouse_stock_daily_items`

Wajib:
- PK `id`
- index `(warehouse_stock_daily_id)`
- index `(variant_id)`
- unique `(warehouse_stock_daily_id, variant_id)` bila memang satu variant satu kali per snapshot

---

## 10. ACTIVITY INDEXES

### 10.1 `activity_logs`

Ini juga tabel besar.

Wajib:
- PK `id`
- index `(user_id, business_date)`
- index `(store_id, business_date)`
- index `(activity_type, business_date)`
- index `(created_at)`

Tambahan:
- index `(user_id, created_at desc)`

### 10.2 `promotion_posts`

Wajib:
- index `(user_id, business_date)`

### 10.3 `follower_events`

Wajib:
- index `(user_id, business_date)`

### 10.4 `vast_applications`

Wajib:
- index `(user_id, business_date)`
- index `(status, business_date)`

---

## 11. ALLBRAND INDEXES

### 11.1 `allbrand_reports`

Wajib:
- PK `id`
- index `(promotor_id, business_date)`
- index `(store_id, business_date)`
- unique `(promotor_id, store_id, business_date)` jika 1 laporan per hari per promotor

### 11.2 `allbrand_report_items`

Wajib:
- PK `id`
- index `(report_id)`
- index `(section_type)`

---

## 12. TARGET INDEXES

### 12.1 `target_periods`

Wajib:
- PK `id`
- unique `(period_name)`
- index `(status, start_date, end_date)`

### 12.2 `user_targets`

Wajib:
- PK `id`
- unique `(period_id, user_id)`
- index `(user_id, period_id)`

### 12.3 `user_target_focus_items`

Wajib:
- index `(user_target_id)`
- index `(variant_id)` atau `(product_id)` sesuai desain final

### 12.4 `user_target_weekly_breakdown`

Wajib:
- unique `(user_target_id, week_no)`

---

## 13. SUMMARY / READ MODEL INDEXES

### 13.1 General Rule

Summary table index harus mengikuti cara dashboard memfilter:
- by period
- by user
- by store
- by area

### 13.2 `dashboard_performance_metrics`

Wajib:
- PK `id`
- unique `(user_id, period_id)`
- index `(period_id, user_id)`

### 13.3 `summary_sales_daily`

Wajib:
- unique sesuai grain tabel
- index `(business_date, user_id)`
- index `(business_date, store_id)`

### 13.4 `summary_sales_monthly`

Wajib:
- index `(period_id, user_id)`
- index `(period_id, store_id)`

### 13.5 `summary_bonus_monthly`

Wajib:
- index `(period_id, user_id)`

### 13.6 `summary_activity_daily`

Wajib:
- index `(business_date, user_id)`

### 13.7 `leaderboard_snapshots`

Wajib:
- index `(period_id, leaderboard_type)`
- index `(period_id, rank_no)`

---

## 14. GOVERNANCE INDEXES

### 14.1 `audit_logs`

Wajib:
- PK `id`
- index `(table_name, record_id, changed_at desc)`
- index `(changed_by, changed_at desc)`
- index `(changed_at desc)`

### 14.2 `error_logs`

Wajib:
- PK `id`
- index `(created_at desc)`
- index `(error_code, created_at desc)`
- index `(user_id, created_at desc)`

### 14.3 `job_runs`

Wajib:
- PK `id`
- index `(job_name, started_at desc)`
- index `(status, started_at desc)`

### 14.4 `idempotency_keys`

Wajib:
- unique `(idempotency_key)`
- index `(created_at)`

---

## 15. INDEX PRIORITY PHASES

### Phase 1: Mandatory Before Go-Live

- semua PK
- semua unique business key
- semua hierarchy access indexes
- semua transaction date composite indexes
- semua approved/active hot path indexes

### Phase 2: Add After Query Observation

- partial indexes tambahan
- reporting-specific composite indexes
- specialized leaderboard indexes

### Phase 3: Scale Optimization

- BRIN/partition-aware strategies untuk tabel sangat besar
- index tuning dari slow query logs

---

## 16. FINAL RULES

- jangan menambah index tanpa alasan query yang jelas
- jangan membiarkan tabel event besar tanpa index waktu dan actor
- semua foreign key lookup yang sering dipakai harus diindex
- semua business unique identifier harus di-protect dengan unique index
- summary table harus diindex sesuai grain dan dimensi laporannya

