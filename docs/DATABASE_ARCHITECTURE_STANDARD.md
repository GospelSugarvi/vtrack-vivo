# DATABASE ARCHITECTURE STANDARD
**Project:** VIVO Sales Management System  
**Platform:** Supabase PostgreSQL  
**Date:** 10 March 2026  
**Status:** FINAL BASELINE FOR IMPLEMENTATION

---

## 1. PURPOSE

Dokumen ini menjadi standar resmi bagaimana database sistem harus dibangun agar:
- tahan banting
- stabil
- cepat
- aman
- bisa diaudit
- bisa berkembang tanpa merusak data lama

Dokumen ini mengikat keputusan inti untuk:
- source of truth
- struktur tabel
- raw data vs aggregate
- indexing
- audit
- access control
- migration discipline

Jika ada konflik antara implementasi dan dokumen ini, implementasi harus disesuaikan ke dokumen ini kecuali ada keputusan baru yang ditulis resmi.

---

## 2. CORE PRINCIPLES

### 2.1 Database Is The Source of Truth

Semua data bisnis penting harus final di database.

Contoh:
- bonus tidak final di client
- approval tidak final di client
- target achievement tidak final di client
- status stok tidak final di client

Frontend hanya mengirim:
- intent
- input user
- filter
- file bukti

Edge Function / RPC:
- validasi request
- jalankan workflow
- panggil function SQL / transaction

Database:
- enforce constraint
- simpan histori
- hitung hasil final

### 2.2 Raw Data First

Semua event bisnis penting harus disimpan sebagai data mentah terlebih dahulu.

Contoh:
- 1 penjualan = 1 row transaksi
- 1 aktivitas = 1 row log
- 1 mutasi stok = 1 row movement
- 1 perubahan status = 1 row history
- 1 kalkulasi bonus = 1 row bonus event

Summary, dashboard, dan leaderboard adalah turunan dari raw data.

### 2.3 Derived Data Is For Speed, Not Truth

Aggregate, summary table, view, dan materialized view dipakai untuk:
- mempercepat query
- mempermudah dashboard
- mempermudah export

Tetapi:
- aggregate bukan sumber utama
- aggregate harus bisa direbuild dari raw data
- data final yang bisa disengketakan harus bisa ditelusuri ke raw data

### 2.4 Financial And Stock Workflows Must Be Transactional

Workflow yang menyentuh uang, bonus, target, stok, atau approval wajib pakai transaction.

Aturan:
- sukses semua = commit
- gagal satu = rollback semua

Tidak boleh ada kondisi setengah jadi.

### 2.5 Auditability Is Mandatory

Semua data penting harus bisa menjawab:
- siapa yang membuat
- siapa yang mengubah
- kapan berubah
- rule apa yang dipakai
- angka itu berasal dari transaksi mana

---

## 3. DATA LAYER MODEL

Database sistem ini wajib dipisah menjadi 4 lapisan.

### 3.1 Master Data Layer

Berisi data referensi yang dipakai sistem.

Contoh:
- `users`
- `stores`
- `products`
- `product_variants`
- `target_periods`
- `bonus_rules_*`
- `hierarchy_*`
- `assignments_*`
- `shift_settings`

Ciri:
- relatif stabil
- dipakai oleh banyak transaksi
- perubahan harus terkontrol

### 3.2 Transaction / Event Layer

Berisi kejadian bisnis mentah.

Contoh:
- `sales_sell_out`
- `sales_sell_in`
- `activity_logs`
- `stock_movements`
- `stock_items` / `stock_imei`
- `chip_requests`
- `order_items`
- `order_status_history`
- `allbrand_reports`
- `promotion_posts`
- `follower_events`
- `vast_applications`

Ciri:
- volume tumbuh terus
- append-heavy
- dasar audit dan perhitungan

### 3.3 Derived / Read Layer

Berisi hasil turunan untuk kebutuhan baca.

Contoh:
- `v_current_store_stock`
- `v_promotor_bonus_running`
- `summary_sales_daily`
- `summary_sales_monthly`
- `summary_activity_daily`
- `summary_bonus_monthly`
- `summary_sell_in_daily`
- `leaderboard_snapshots`

Ciri:
- dibangun dari raw data
- optimize untuk read
- bisa direfresh / rebuild

### 3.4 Governance Layer

Berisi pengaman dan observability.

Contoh:
- `audit_logs`
- `error_logs`
- `job_runs`
- `idempotency_keys`
- `rule_snapshots`
- `recalc_requests`

---

## 4. SOURCE OF TRUTH BY DOMAIN

### 4.1 Sell Out / Penjualan

Source of truth:
- tabel transaksi per penjualan
- jika basis IMEI, maka 1 IMEI = 1 unit transaksi final

Wajib simpan:
- `promotor_id`
- `store_id`
- `variant_id`
- `transaction_date`
- `serial_imei`
- `price_at_transaction`
- `payment_method`
- `leasing_provider` jika ada
- `status`
- `created_at`
- `created_by`

Derived data:
- omzet harian
- omzet bulanan
- unit harian
- achievement
- leaderboard

### 4.2 Bonus

Source of truth bonus bukan summary omzet, tetapi hasil kalkulasi per event.

Wajib ada:
- tabel event bonus atau detail bonus per transaksi
- referensi atau snapshot rule yang dipakai

Contoh isi minimal:
- `sales_id`
- `user_id`
- `period_id`
- `bonus_type`
- `rule_id` atau `rule_snapshot`
- `bonus_amount`
- `calculated_at`
- `calculation_version`

Aggregate bonus dipakai untuk dashboard, tetapi sumber audit tetap bonus event detail.

### 4.3 Activity

Source of truth:
- activity event log per kejadian

Contoh:
- `clock_in`
- `stock_check`
- `promotion_submit`
- `allbrand_submit`
- `visit_start`
- `visit_finish`

Derived data:
- checklist aktivitas harian
- days active
- missing activity alerts
- monthly discipline metrics

### 4.4 Stock

Source of truth stok harus berbasis item atau movement, bukan angka total manual.

Struktur ideal:
- `stock_items` / `stock_imei`
- `stock_movements`

Contoh movement:
- incoming
- chip
- sold
- transfer_out
- transfer_in
- relocate
- return
- adjustment

Current stock dibaca dari view atau summary hasil agregasi movement / item status.

### 4.5 Sell In / Order Recommendation / Fulfillment

Source of truth:
- order header
- order items
- order status history
- warehouse stock snapshot harian sebagai reference

Catatan:
- `warehouse_stock_daily` adalah reference input
- bukan warehouse system of record global

### 4.6 Targets

Source of truth target:
- `target_periods`
- `user_targets`
- tabel detail fokus / bundle / weekly breakdown bila ada

Achievement target harus dihitung dari raw transaction dan disajikan via derived layer.

### 4.7 AllBrand / Manual External Inputs

Karena sebagian data berasal dari input manual, maka yang disimpan harus tetap raw submission.

Jangan simpan hanya total summary.

Wajib ada:
- siapa submit
- toko mana
- tanggal bisnis
- brand
- range harga
- qty / value
- bukti jika ada

---

## 5. RAW DATA VS AGGREGATE RULES

### 5.1 Raw Data Must Exist For

Raw data wajib ada untuk:
- penjualan
- bonus detail
- aktivitas
- stok movement
- approval
- target changes
- order changes
- manual input eksternal

### 5.2 Aggregate Is Allowed For

Aggregate wajib dipakai untuk:
- dashboard cepat
- leaderboard
- monthly recap
- team summary
- export summary
- cards dan charts

### 5.3 Aggregate Restrictions

Aggregate tidak boleh:
- menjadi satu-satunya sumber angka finansial
- menjadi satu-satunya sumber angka bonus
- diubah manual dari frontend
- menyimpan logika yang tidak bisa ditrace ke raw

### 5.4 Rebuildability Rule

Setiap aggregate penting harus memenuhi salah satu:
- bisa direbuild penuh dari raw data
- atau punya job refresh resmi yang deterministic

---

## 6. TABLE DESIGN RULES

### 6.1 Primary Key Standard

Gunakan `uuid` untuk entity utama.

Contoh:
- users
- stores
- products
- transactions
- order headers

### 6.2 Timestamp Standard

Gunakan:
- `created_at timestamptz not null default now()`
- `updated_at timestamptz` bila record mutable

Tanggal bisnis tetap simpan terpisah bila perlu:
- `transaction_date date`
- `period_month date` atau representasi periode resmi

### 6.3 Money Standard

Pakai `numeric`, jangan `float` / `double precision` untuk uang.

### 6.4 Status Standard

Status penting harus konsisten:
- pakai enum bila status benar-benar terbatas dan stabil
- pakai reference table bila status berpotensi berkembang

Jangan campur banyak arti dalam satu kolom text tanpa definisi resmi.

### 6.5 Snapshot Standard

Snapshot wajib disimpan jika nilai master bisa berubah dan histori transaksi harus tetap benar.

Contoh:
- `price_at_transaction`
- `role_at_time`
- `store_name_snapshot` jika export historis membutuhkannya
- `rule_snapshot`

### 6.6 Soft Delete Rule

Untuk data master penting, lebih aman pakai:
- `status`
- `active boolean`

Daripada hard delete.

Hard delete hanya untuk data yang memang aman dihapus dan tidak punya histori bisnis.

---

## 7. CONSTRAINT RULES

Setiap tabel penting wajib punya constraint yang relevan.

### 7.1 Required Constraints

- primary key
- foreign key
- not null untuk field inti
- unique untuk identifier bisnis
- check untuk nilai numerik dan status valid

### 7.2 Examples

Contoh aturan yang wajib ditegakkan:
- 1 IMEI tidak boleh duplikat
- quantity tidak boleh minus
- bonus amount tidak boleh minus jika bukan reversal
- target value tidak boleh minus
- satu assignment aktif tidak boleh ganda untuk relasi yang harus tunggal
- satu transaksi tidak boleh dihitung bonus dua kali tanpa record reversal/resettlement resmi

### 7.3 Constraint Before Code Rule

Kalau sebuah aturan bisa dijaga oleh database, jangan hanya dijaga di Flutter.

---

## 8. WRITE WORKFLOW RULES

### 8.1 All Important Writes Go Through Controlled Path

Write penting harus lewat salah satu:
- RPC / stored function
- edge function
- server-side transaction

Hindari write langsung ke banyak tabel dari client untuk workflow sensitif.

### 8.2 Idempotency

Workflow yang berisiko terpanggil ulang wajib punya idempotency.

Contoh:
- submit penjualan
- submit stok masuk
- finalize sell in
- recalc bonus
- bulk upsert gudang

### 8.3 Status Transition Control

Status tidak boleh loncat bebas.

Perlu aturan resmi:
- allowed transition
- siapa boleh mengubah
- kapan timestamp dicatat
- apakah perlu history row

---

## 9. BONUS CALCULATION RULES

### 9.1 Bonus Must Be Event-Based

Bonus harus dihitung dari transaksi mentah, bukan dari total summary akhir semata.

### 9.2 Rule Snapshot Is Mandatory

Karena rule bonus bisa berubah, hasil kalkulasi bonus harus terkait ke:
- `rule_id` aktif saat itu
- atau snapshot JSON rule saat transaksi dihitung

### 9.3 Recalculation Must Be Explicit

Kalau bonus perlu dihitung ulang:
- harus ada job / request resmi
- harus tercatat
- hasil lama jangan hilang tanpa jejak

### 9.4 Projection vs Final

Pisahkan jelas:
- bonus projection
- bonus locked/finalized

Projection boleh derived.
Final payout trace wajib ada di bonus detail dan settlement record.

---

## 10. STOCK ARCHITECTURE RULES

### 10.1 Store Stock

Stok toko harus berbasis unit atau movement.

Jika produk ber-IMEI:
- 1 row per IMEI sangat dianjurkan

### 10.2 Warehouse Stock

Karena warehouse system utama ada di luar sistem ini, maka stok gudang internal diklasifikasikan sebagai:
- `daily operational reference`

Aturan:
- simpan snapshot per tanggal
- simpan siapa input
- jangan samakan dengan real warehouse truth global

### 10.3 No Manual Final Quantity Rule

Angka current stock tidak boleh hanya diandalkan dari input manual total akhir tanpa jejak movement.

---

## 11. READ MODEL RULES

### 11.1 View First

Untuk agregasi ringan dan selalu fresh, gunakan SQL view.

### 11.2 Materialized View Or Summary Table For Heavy Queries

Gunakan materialized view atau summary table jika:
- query dashboard berat
- data transaksi sudah besar
- leaderboard sering dibuka
- export butuh performa tinggi

### 11.3 Summary Naming

Gunakan naming yang tegas:
- `v_*` untuk view
- `mv_*` untuk materialized view
- `summary_*` untuk tabel summary fisik

### 11.4 Summary Ownership

Setiap summary harus jelas:
- sumber datanya apa
- refresh-nya kapan
- siapa yang membangun
- bisa direbuild bagaimana

---

## 12. INDEXING STANDARD

### 12.1 Why Indexing Is Mandatory

Karena sistem ini akan banyak query berdasarkan:
- user
- role hierarchy
- store
- product / variant
- status
- date range
- period

Tanpa indexing, query reporting dan dashboard akan melambat seiring pertumbuhan data.

### 12.2 Mandatory Index Categories

Wajib index:
- primary key
- foreign key lookup columns
- tanggal transaksi
- periode
- status yang sering difilter
- kombinasi kolom query utama

### 12.3 Common Composite Index Patterns

Contoh pola umum:
- `(promotor_id, transaction_date)`
- `(store_id, transaction_date)`
- `(sator_id, transaction_date)`
- `(user_id, created_at)`
- `(store_id, variant_id, status)`
- `(period_id, user_id)`
- `(status, transaction_date)`

### 12.4 Unique Index For Business Identifiers

Contoh:
- `serial_imei`
- kombinasi assignment aktif tertentu jika harus unik
- kombinasi tanggal + produk pada snapshot gudang bila memang satu row per hari

### 12.5 Partial Index

Gunakan partial index bila query dominan hanya menyentuh sebagian data.

Contoh:
- row status approved
- row active = true
- row deleted_at is null

### 12.6 Index Discipline

Jangan index semua kolom.

Terlalu banyak index:
- memperlambat insert/update
- memperberat maintenance

Index harus mengikuti pola query nyata.

---

## 13. RLS AND ACCESS CONTROL STANDARD

### 13.1 Database Security Must Not Depend On Flutter UI

Menu disembunyikan di UI bukan security.

Security final harus di database.

### 13.2 Hierarchy-Based Access

Akses data harus mengikuti assignment resmi.

Aturan minimum:
- promotor: data sendiri / toko penugasan sendiri
- sator: data promotor dan toko yang berada di bawah scope-nya
- spv: data area / sator bawahannya
- manager/admin: sesuai scope yang ditentukan

### 13.3 Least Privilege

Pisahkan hak:
- SELECT
- INSERT
- UPDATE
- DELETE

Jangan pakai policy terlalu longgar hanya demi cepat jalan.

### 13.4 Sensitive Data Segregation

Beberapa data perlu pembatasan tambahan:
- breakdown gaji tetap
- bonus detail orang lain
- data customer sensitif
- log internal audit

---

## 14. AUDIT STANDARD

### 14.1 Mandatory Audit Coverage

Audit wajib untuk:
- perubahan target
- perubahan bonus rule
- approval chip
- perubahan assignment hierarchy
- koreksi penjualan
- koreksi stok
- perubahan status order

### 14.2 Audit Content

Minimal simpan:
- table_name
- record_id
- action
- old_data
- new_data
- changed_by
- changed_at

### 14.3 No Silent Rewrite

Untuk data sensitif, jangan lakukan overwrite diam-diam tanpa jejak audit.

---

## 15. PERFORMANCE AND SCALABILITY STANDARD

### 15.1 Design For Growth

Tabel besar diperkirakan:
- sales
- activity_logs
- stock_movements
- audit_logs
- notifications

Schema harus siap tumbuh tanpa redesign total.

### 15.2 Archival Strategy

Data lama boleh diarsipkan, tetapi:
- jangan merusak audit trail
- jangan memutus kemampuan rebuild aggregate penting

### 15.3 Partition Readiness

Jika volume sudah besar, siapkan strategi partisi untuk tabel event utama per bulan/periode.

Tidak wajib langsung hari pertama, tetapi desain key dan query harus siap.

---

## 16. MIGRATION STANDARD

### 16.1 Migration Is The Only Official Schema Change Path

Perubahan schema harus masuk migration versioned.

Tidak boleh mengandalkan perubahan manual tanpa jejak.

### 16.2 Migration Content

Migration wajib jelas memuat:
- tujuan
- object yang diubah
- dampak backward compatibility
- data backfill jika perlu
- verification query jika perlu

### 16.3 Safe Change Rule

Untuk perubahan berisiko:
- tambah kolom dulu
- backfill
- ubah code
- verifikasi
- baru drop legacy di fase berikutnya

### 16.4 Legacy Object Rule

Tabel legacy:
- harus diberi deprecation note
- harus diblok write baru jika sudah tidak dipakai
- drop hanya setelah verifikasi penuh

---

## 17. OPERATIONAL GOVERNANCE

### 17.1 Required Operational Checks

Harus ada audit rutin untuk:
- tabel frontend yang belum ada
- RPC yang belum ada
- tabel frontend dengan RLS off
- policy count nol
- object legacy yang masih kena write

### 17.2 Error Logging

Setiap workflow penting harus punya jejak error yang bisa dianalisis.

### 17.3 Recovery Readiness

Backup dan restore harus dianggap bagian dari sistem, bukan urusan belakangan.

---

## 18. PRACTICAL DECISION FOR THIS PROJECT

Keputusan final untuk sistem ini:

- `Raw transaction tables` adalah sumber kebenaran utama
- `Aggregate / summary` wajib ada untuk performa
- `Bonus` wajib event-based dan traceable ke transaksi
- `Stock` wajib berbasis item atau movement, bukan total manual final
- `Activity` wajib berbasis event log
- `Order / Sell In` wajib punya header, detail, dan status history
- `Warehouse stock daily` diklasifikasikan sebagai reference snapshot, bukan absolute warehouse truth
- `RLS` wajib aktif pada semua tabel yang disentuh frontend
- `Migration` adalah jalur resmi perubahan schema
- `Audit log` wajib untuk perubahan data sensitif

---

## 19. IMPLEMENTATION ORDER

Urutan kerja yang benar setelah dokumen ini:

1. Lock source of truth per domain
2. Finalkan daftar tabel per layer
3. Finalkan relasi PK/FK dan constraint
4. Finalkan write workflow transactional
5. Finalkan summary/view strategy
6. Finalkan indexing pack
7. Finalkan RLS matrix per role
8. Finalkan audit tables dan trigger
9. Tulis migration bertahap
10. Verifikasi performa dan akses

---

## 20. NON-NEGOTIABLE RULES

Hal-hal ini tidak boleh dilanggar:

- jangan jadikan aggregate sebagai satu-satunya sumber angka final
- jangan hitung bonus final di frontend
- jangan simpan current stock hanya sebagai angka manual tanpa jejak
- jangan ubah schema production tanpa migration
- jangan mengandalkan UI hiding sebagai security
- jangan overwrite data sensitif tanpa audit
- jangan menambah fitur baru yang menulis ke tabel legacy deprecated

---

## 21. NEXT DOCUMENTS TO DERIVE FROM THIS STANDARD

Dokumen ini menjadi dasar untuk menurunkan:
- final schema blueprint
- indexing blueprint
- RLS blueprint
- audit blueprint
- migration roadmap
- cleanup roadmap untuk object legacy

