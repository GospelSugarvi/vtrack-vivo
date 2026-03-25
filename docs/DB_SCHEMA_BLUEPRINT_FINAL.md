# DB SCHEMA BLUEPRINT FINAL
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** ACTIVE BLUEPRINT

---

## 1. PURPOSE

Dokumen ini menurunkan [DATABASE_ARCHITECTURE_STANDARD.md](./DATABASE_ARCHITECTURE_STANDARD.md) menjadi blueprint schema final.

Fungsi dokumen ini:
- menentukan tabel inti per domain
- memisahkan tabel raw vs summary
- menetapkan source of truth
- menetapkan tabel legacy yang tidak boleh jadi acuan desain baru

Dokumen ini adalah acuan desain schema ke depan. Draft schema lama tetap bisa dipakai sebagai referensi historis, tetapi keputusan final mengikuti dokumen ini.

---

## 2. SCHEMA LAYERS

### 2.1 Master Layer

Tabel master:
- `users`
- `stores`
- `store_groups`
- `products`
- `product_variants`
- `target_periods`
- `bonus_rules_range`
- `bonus_rules_flat`
- `bonus_rules_ratio`
- `bonus_kpi_settings`
- `shift_settings`

Tabel relasi/hierarchy:
- `hierarchy_manager_spv`
- `hierarchy_spv_sator`
- `hierarchy_sator_promotor`
- `assignments_promotor_store`
- `assignments_sator_store`

### 2.2 Transaction / Event Layer

Tabel transaksi/event:
- `sales_sell_out`
- `sales_sell_out_status_history`
- `sales_bonus_events`
- `sales_sell_in_orders`
- `sales_sell_in_order_items`
- `sales_sell_in_status_history`
- `stock_items`
- `stock_movements`
- `chip_requests`
- `chip_request_history`
- `activity_logs`
- `allbrand_reports`
- `allbrand_report_items`
- `promotion_posts`
- `follower_events`
- `vast_applications`
- `warehouse_stock_daily`
- `warehouse_stock_daily_items`

### 2.3 Derived / Read Layer

View / summary:
- `v_current_store_stock`
- `v_promotor_sellout_daily`
- `v_promotor_bonus_running`
- `summary_sales_daily`
- `summary_sales_monthly`
- `summary_bonus_monthly`
- `summary_activity_daily`
- `summary_sell_in_daily`
- `summary_target_achievement_monthly`
- `leaderboard_snapshots`
- `dashboard_performance_metrics`

### 2.4 Governance Layer

Tabel governance:
- `audit_logs`
- `error_logs`
- `job_runs`
- `idempotency_keys`
- `rule_snapshots`
- `recalc_requests`

---

## 3. MASTER TABLES

### 3.1 `users`

Tujuan:
- identitas user aplikasi
- role resmi
- status aktif/nonaktif

Kolom inti:
- `id uuid primary key`
- `username text unique not null`
- `full_name text not null`
- `role user_role not null`
- `area text`
- `status text not null default 'active'`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Catatan:
- data auth tetap mengacu ke `auth.users`
- data profil bisnis berada di tabel ini

### 3.2 `stores`

Kolom inti:
- `id uuid primary key`
- `store_name text not null`
- `area text not null`
- `grade text`
- `address text`
- `status text not null default 'active'`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

### 3.3 Hierarchy Tables

Tabel:
- `hierarchy_manager_spv`
- `hierarchy_spv_sator`
- `hierarchy_sator_promotor`
- `assignments_promotor_store`
- `assignments_sator_store`

Aturan:
- relasi aktif harus bisa ditentukan jelas
- histori assignment lama tidak dihapus
- jika perlu, tambahkan `effective_from`, `effective_to`

### 3.4 `products`

Kolom inti:
- `id`
- `model_name`
- `series`
- `status`
- `is_focus`
- `is_npo`
- `bonus_type`
- `ratio_val`
- `flat_bonus`
- `created_at`
- `updated_at`

Catatan:
- ini master bisnis
- tidak menyimpan angka transaksi

### 3.5 `product_variants`

Kolom inti:
- `id`
- `product_id`
- `ram_rom`
- `color`
- `srp`
- `active`
- `created_at`
- `updated_at`

### 3.6 `target_periods`

Kolom inti:
- `id`
- `period_name`
- `start_date`
- `end_date`
- `status`
- `weekly_config`
- `created_at`
- `updated_at`

### 3.7 Bonus Rule Masters

Pisahkan rule agar audit dan query lebih jelas:
- `bonus_rules_range`
- `bonus_rules_flat`
- `bonus_rules_ratio`

Jangan pakai satu tabel serba campur jika itu membuat validasi dan audit jadi kabur.

---

## 4. SELL OUT DOMAIN

### 4.1 `sales_sell_out`

Ini source of truth penjualan promotor.

Kolom inti:
- `id uuid primary key`
- `promotor_id uuid not null references users(id)`
- `store_id uuid not null references stores(id)`
- `variant_id uuid not null references product_variants(id)`
- `transaction_date date not null`
- `serial_imei text not null`
- `price_at_transaction numeric not null`
- `payment_method text`
- `leasing_provider text`
- `customer_name text`
- `status text not null`
- `image_proof_url text`
- `created_at timestamptz not null default now()`
- `created_by uuid`
- `updated_at timestamptz`

Aturan:
- `serial_imei` wajib unik untuk transaksi final per unit
- `price_at_transaction` adalah snapshot
- jangan simpan bonus final hanya di tabel ini

### 4.2 `sales_sell_out_status_history`

Tujuan:
- jejak perubahan status penjualan

Kolom inti:
- `id`
- `sales_sell_out_id`
- `old_status`
- `new_status`
- `changed_at`
- `changed_by`
- `notes`

### 4.3 `sales_bonus_events`

Ini source of truth bonus per event transaksi.

Kolom inti:
- `id`
- `sales_sell_out_id`
- `user_id`
- `period_id`
- `bonus_type`
- `rule_id`
- `rule_snapshot jsonb`
- `bonus_amount numeric`
- `calculation_version text`
- `is_projection boolean`
- `created_at`

Aturan:
- 1 transaksi bisa punya 1 atau lebih row bonus event jika ada reversal/adjustment resmi
- bonus dashboard harus menjumlah dari tabel ini

---

## 5. SELL IN DOMAIN

### 5.1 `sales_sell_in_orders`

Tujuan:
- header order / rekomendasi order / proses sell-in

Kolom inti:
- `id`
- `sator_id`
- `store_id`
- `business_date`
- `source_type`
- `status`
- `total_qty`
- `total_value`
- `notes`
- `created_at`
- `created_by`

### 5.2 `sales_sell_in_order_items`

Kolom inti:
- `id`
- `order_id`
- `variant_id`
- `recommended_qty`
- `approved_qty`
- `submitted_qty`
- `unit_price_snapshot`
- `line_total`

### 5.3 `sales_sell_in_status_history`

Status history wajib ada untuk trace:
- sent
- approved
- partially_approved
- rejected
- submitted_to_warehouse
- delivered
- cancelled

---

## 6. STOCK DOMAIN

### 6.1 `stock_items`

Jika stok berbasis IMEI, ini tabel unit utama.

Kolom inti:
- `id`
- `serial_imei`
- `variant_id`
- `current_store_id`
- `stock_type`
- `current_status`
- `is_sold`
- `received_at`
- `sold_at`
- `created_at`

Catatan:
- 1 unit fisik = 1 row
- `serial_imei` wajib unik

### 6.2 `stock_movements`

Ini ledger mutasi stok dan salah satu source of truth terpenting.

Kolom inti:
- `id`
- `stock_item_id`
- `movement_type`
- `from_store_id`
- `to_store_id`
- `related_sale_id`
- `related_chip_request_id`
- `business_date`
- `notes`
- `created_at`
- `created_by`

Movement type contoh:
- incoming
- chip
- display
- sold
- transfer_out
- transfer_in
- relocation
- return
- adjustment

### 6.3 `chip_requests`

Kolom inti:
- `id`
- `stock_item_id`
- `promotor_id`
- `sator_id`
- `reason`
- `status`
- `requested_at`
- `approved_at`
- `approved_by`

### 6.4 `chip_request_history`

Status history approval chip.

### 6.5 Warehouse Reference

Tabel:
- `warehouse_stock_daily`
- `warehouse_stock_daily_items`

Klasifikasi:
- reference snapshot
- bukan absolute global warehouse source of truth

Ini dipakai untuk:
- rekomendasi order
- monitoring stok gudang harian

---

## 7. ACTIVITY DOMAIN

### 7.1 `activity_logs`

Source of truth aktivitas user.

Kolom inti:
- `id`
- `user_id`
- `store_id`
- `activity_type`
- `business_date`
- `data jsonb`
- `created_at`
- `created_by`

Catatan:
- event-based
- jangan cuma simpan total checklist

### 7.2 Social / Daily Manual Activity Tables

Tabel terpisah bisa dipakai jika payload makin spesifik:
- `promotion_posts`
- `follower_events`
- `vast_applications`

Tetapi `activity_logs` tetap bisa menjadi event trail umumnya.

---

## 8. ALLBRAND DOMAIN

### 8.1 `allbrand_reports`

Header laporan harian promotor.

Kolom inti:
- `id`
- `promotor_id`
- `store_id`
- `business_date`
- `submitted_at`
- `submitted_by`
- `notes`

### 8.2 `allbrand_report_items`

Detail per brand / range harga / leasing / jumlah promotor.

Kolom inti:
- `id`
- `report_id`
- `section_type`
- `brand_name`
- `price_range`
- `metric_name`
- `metric_value`

Catatan:
- jangan pakai hanya satu blob summary besar kalau nanti perlu audit/detail per item

---

## 9. TARGET DOMAIN

### 9.1 `user_targets`

Kolom inti:
- `id`
- `period_id`
- `user_id`
- `role_at_time`
- `target_omzet`
- `target_sell_in`
- `target_tiktok_follow`
- `target_vast_submissions`
- `updated_at`
- `updated_by`

### 9.2 Detail Target Tables

Daripada terlalu berat di JSON, target spesifik sebaiknya dipisah:
- `user_target_focus_items`
- `user_target_weekly_breakdown`

Ini lebih baik untuk:
- validasi
- query
- audit

### 9.3 `summary_target_achievement_monthly`

Derived table/view dari:
- `user_targets`
- `sales_sell_out`
- `sales_sell_in_orders`
- `promotion_posts`
- `follower_events`
- `vast_applications`

---

## 10. DERIVED / SUMMARY TABLES

### 10.1 Principles

Derived layer tidak boleh menjadi source of truth utama.

### 10.2 Recommended Objects

Minimal:
- `v_current_store_stock`
- `summary_sales_daily`
- `summary_sales_monthly`
- `summary_bonus_monthly`
- `summary_activity_daily`
- `summary_sell_in_daily`
- `summary_target_achievement_monthly`
- `dashboard_performance_metrics`

### 10.3 `dashboard_performance_metrics`

Tabel ini boleh dipertahankan sebagai summary cepat, tetapi statusnya adalah:
- read model
- bukan source of truth utama

Jangan masukkan field yang tidak bisa direbuild dari raw data.

---

## 11. GOVERNANCE TABLES

### 11.1 `audit_logs`

Wajib ada untuk perubahan data sensitif.

### 11.2 `error_logs`

Wajib ada untuk mencatat kegagalan workflow penting.

### 11.3 `job_runs`

Untuk:
- refresh summary
- recalculation
- scheduled maintenance

### 11.4 `idempotency_keys`

Untuk melindungi proses submit penting dari double execution.

### 11.5 `rule_snapshots`

Dipakai untuk menyimpan snapshot rule jika pemisahan dari event table dibutuhkan.

---

## 12. EXPLICITLY DEPRECATED AS PRIMARY MODEL

Struktur berikut tidak boleh jadi model utama desain ke depan:

- `store_inventory` sebagai satu-satunya source of truth stok
- kolom bonus total yang hanya ditaruh langsung di transaksi tanpa event detail
- summary dashboard yang diupdate manual dari client
- tabel legacy warehouse lama yang sudah deprecated

Jika object ini masih ada di DB:
- boleh dipakai sementara untuk backward compatibility
- tidak boleh jadi basis fitur baru

---

## 13. IMPLEMENTATION PRIORITY

Urutan implementasi schema yang benar:

1. lock master + hierarchy tables
2. lock sell out + bonus event tables
3. lock stock item + stock movement tables
4. lock sell in order tables
5. lock activity + allbrand tables
6. lock target detail tables
7. bangun derived layer
8. bangun audit, error log, dan job tables

---

## 14. FINAL DECISIONS

Keputusan final schema:
- penjualan berbasis transaksi mentah
- bonus berbasis event detail
- stok berbasis item/movement
- aktivitas berbasis event log
- target disimpan di master target + detail target
- dashboard membaca dari derived layer
- warehouse stock harian adalah snapshot referensi

