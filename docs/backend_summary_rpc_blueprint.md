# Backend Summary And RPC Blueprint

Dokumen ini menetapkan desain backend ringan untuk schema baru.  
Tujuannya: loading cepat, query ringan, dan aman dipakai di Supabase free tier.

## Prinsip inti

- layar `Home` tidak boleh membaca transaksi mentah besar
- `Ranking` tidak boleh menghitung ulang dari raw table tiap buka layar
- data operasional dipisah dari data baca cepat
- yang sering dibuka harus membaca summary
- raw table dipakai untuk detail, audit, dan histori

## Arsitektur 3 lapis

### 1. Fact tables

Tabel sumber kejadian asli.

Contoh:

- `fact_sell_out`
- `fact_sell_in`
- `fact_attendance`
- `fact_visit`
- `fact_stock_event`
- `fact_chat_event`

Fungsi:

- sumber audit
- sumber histori
- sumber detail transaksi

### 2. Summary tables

Tabel agregat untuk baca cepat.

Contoh:

- `summary_user_daily`
- `summary_store_daily`
- `summary_team_daily`
- `summary_user_period`
- `summary_team_period`
- `summary_leaderboard_daily`
- `summary_leaderboard_period`

Fungsi:

- dashboard
- leaderboard
- ringkasan monitoring
- alert

### 3. RPC read layer

RPC tipis yang membaca summary, bukan menghitung berat lagi.

Contoh:

- `get_promotor_home_summary`
- `get_sator_home_summary`
- `get_spv_home_summary`
- `get_manager_home_summary`
- `get_trainer_home_summary`

## Fact tables inti

### `fact_sell_out`

Satu baris per transaksi jual.

Kolom inti:

- `id`
- `transaction_at`
- `transaction_date`
- `promotor_user_id`
- `store_id`
- `spv_user_id`
- `sator_user_id`
- `product_id`
- `brand_id`
- `qty`
- `amount`
- `is_focus_product`
- `is_special_type`
- `period_id`

Fungsi:

- sumber utama sell out
- bisa diroll-up ke semua role

### `fact_sell_in`

Satu baris per kejadian sell in/order.

Kolom inti:

- `id`
- `transaction_at`
- `transaction_date`
- `sator_user_id`
- `store_id`
- `amount`
- `qty`
- `period_id`

### `fact_attendance`

Satu baris per kehadiran harian.

Kolom inti:

- `id`
- `user_id`
- `attendance_date`
- `clock_in_at`
- `clock_out_at`
- `status`

### `fact_visit`

Satu baris per kunjungan.

Kolom inti:

- `id`
- `visit_date`
- `sator_user_id`
- `store_id`
- `visit_status`

### `fact_stock_event`

Satu baris per kejadian stok.

Kolom inti:

- `id`
- `event_at`
- `event_date`
- `store_id`
- `actor_user_id`
- `event_type`
- `product_id`
- `qty`
- `reference_id`

`event_type` resmi:

- `stock_opname`
- `stock_adjustment`
- `stock_transfer_in`
- `stock_transfer_out`
- `stock_validation`
- `stock_return`

## Summary tables wajib

### `summary_user_daily`

Grain:

- satu user per tanggal

Kolom inti:

- `user_id`
- `role_code`
- `summary_date`
- `spv_user_id`
- `sator_user_id`
- `store_id`
- `sell_out_all_type_actual`
- `focus_product_actual`
- `special_type_actual`
- `sell_in_actual`
- `attendance_status`
- `visit_count`
- `activity_score`

Dipakai untuk:

- home promotor
- home trainer
- monitoring cepat

### `summary_store_daily`

Grain:

- satu toko per tanggal

Kolom inti:

- `store_id`
- `summary_date`
- `sell_out_all_type_actual`
- `focus_product_actual`
- `sell_in_actual`
- `active_promotor_count`
- `visit_count`
- `stock_event_count`

Dipakai untuk:

- monitoring toko
- visiting
- progress operasional

### `summary_team_daily`

Grain:

- satu owner role per tanggal

Kolom inti:

- `owner_user_id`
- `owner_role_code`
- `summary_date`
- `sell_out_all_type_actual`
- `focus_product_actual`
- `sell_in_actual`
- `active_member_count`
- `inactive_member_count`
- `active_store_count`
- `pending_approval_count`
- `blocked_work_count`

Dipakai untuk:

- home SATOR
- home SPV
- home Manager

### `summary_user_period`

Grain:

- satu user per periode

Kolom inti:

- `user_id`
- `role_code`
- `period_id`
- `sell_out_all_type_target`
- `sell_out_all_type_actual`
- `focus_product_target`
- `focus_product_actual`
- `sell_in_target`
- `sell_in_actual`
- `achievement_pct_sell_out_all_type`
- `achievement_pct_focus_product`
- `achievement_pct_sell_in`

Dipakai untuk:

- target bulanan
- detail target
- bonus dependency

### `summary_team_period`

Grain:

- satu owner role per periode

Kolom inti:

- `owner_user_id`
- `owner_role_code`
- `period_id`
- `sell_out_all_type_target`
- `sell_out_all_type_actual`
- `focus_product_target`
- `focus_product_actual`
- `sell_in_target`
- `sell_in_actual`

Dipakai untuk:

- home period SATOR
- home period SPV
- home period Manager

### `summary_leaderboard_daily`

Grain:

- satu user per tanggal per ranking scope

Kolom inti:

- `summary_date`
- `scope_role_code`
- `scope_user_id`
- `ranked_user_id`
- `ranked_role_code`
- `rank_position`
- `score_sell_out_all_type_pct`
- `score_focus_product_pct`
- `final_score`

Dipakai untuk:

- ranking cepat
- best performance harian

### `summary_leaderboard_period`

Grain:

- satu user per periode per ranking scope

Kolom inti:

- `period_id`
- `scope_role_code`
- `scope_user_id`
- `ranked_user_id`
- `ranked_role_code`
- `rank_position`
- `score_sell_out_all_type_pct`
- `score_focus_product_pct`
- `final_score`

Dipakai untuk:

- ranking mingguan
- ranking bulanan
- best performance mingguan
- best performance bulanan

## Scope ranking

Ranking harus disimpan per scope, bukan dihitung liar.

Contoh scope:

- `promotor_area_kupang`
- `sator_under_manager`
- `promotor_under_spv`
- `spv_under_manager`

Aturan dari keputusan produk:

- promotor ranking area Kupang dulu
- SATOR melihat ranking SATOR dan promotor dalam cakupan SPV yang sama
- SPV melihat ranking SATOR dan promotor
- trainer melihat ranking promotor
- manager melihat ranking SPV, SATOR, promotor

## Tabel target

Target inti tetap dibaca dari tabel target utama schema baru:

- `app_target_periods`
- `app_target_period_weeks`
- `app_user_targets`

Summary target harus menurunkan istilah resmi:

- `sell_out_all_type_target`
- `focus_product_target`
- `sell_in_target`

## Cara update summary

Jangan update berat saat layar dibuka.

Pola resmi:

1. transaksi masuk ke fact table
2. trigger ringan memasukkan antrean recalc
3. job worker memproses batch
4. summary table di-update
5. RPC dashboard membaca summary

## Tabel antrean

### `summary_recalc_queue`

Kolom inti:

- `id`
- `summary_kind`
- `entity_type`
- `entity_id`
- `target_date`
- `target_period_id`
- `status`
- `attempt_count`
- `last_error`
- `created_at`
- `processed_at`

`summary_kind` contoh:

- `user_daily`
- `store_daily`
- `team_daily`
- `user_period`
- `team_period`
- `leaderboard_daily`
- `leaderboard_period`

## RPC resmi yang dibutuhkan

### Home RPC

- `get_promotor_home_summary`
- `get_sator_home_summary`
- `get_spv_home_summary`
- `get_manager_home_summary`
- `get_trainer_home_summary`

Aturan:

- satu RPC home maksimal membaca 1 sampai 3 summary table
- jangan hit raw transaction besar

### Workplace RPC

- `get_promotor_workplace_summary`
- `get_sator_workplace_summary`
- `get_spv_workplace_summary`
- `get_trainer_workplace_summary`
- `get_manager_workplace_summary`

### Ranking RPC

- `get_promotor_ranking`
- `get_sator_ranking`
- `get_spv_ranking`
- `get_trainer_ranking`
- `get_manager_ranking`

Aturan:

- ranking RPC membaca summary leaderboard
- bukan hitung ulang dari fact table

### Detail RPC

- `get_target_detail`
- `get_sell_out_detail`
- `get_sell_in_detail`
- `get_visit_detail`
- `get_product_training_detail`

Aturan:

- detail boleh membaca fact table
- home dan ranking tidak

## Auto post best performance

Karena ada fitur poster otomatis malam hari, backend perlu:

### `motivational_posts`

Kolom inti:

- `id`
- `period_kind`
- `category_code`
- `scope_user_id`
- `winner_user_ids`
- `image_path`
- `posted_room_id`
- `scheduled_at`
- `posted_at`
- `status`

`period_kind`:

- `daily`
- `weekly`
- `monthly`

`category_code`:

- `sell_out_all_type`
- `focus_product`

Aturan sesuai keputusan user:

- dijalankan `22:00 WITA`
- kirim ke grup global per SPV
- jika seri tampilkan 2 orang

## Query guardrails

Aturan performa wajib:

- semua summary punya unique grain yang jelas
- semua kolom filter utama harus terindeks
- semua RPC home dibatasi payload kecil
- semua list wajib pagination
- semua chart membaca summary
- semua export berat dipindah ke job async

## Larangan teknis

- jangan baca `fact_sell_out` langsung untuk home
- jangan hitung leaderboard realtime dari raw data
- jangan campur summary harian dan bulanan dalam satu tabel tanpa grain jelas
- jangan bikin RPC baru kalau summary lama sudah punya arti yang sama
- jangan bikin tabel duplikat untuk role tertentu jika struktur generiknya sudah cukup
