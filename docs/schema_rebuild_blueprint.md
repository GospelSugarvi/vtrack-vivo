# Schema Rebuild Blueprint

Tujuan dokumen ini: mengganti fondasi lama yang tumpang tindih dengan schema baru yang kecil, tegas, dan bisa dikembangkan.

## Role final

Role resmi yang dipakai aplikasi:

- `admin`
- `manager`
- `spv`
- `trainer`
- `sator`
- `promotor`

Catatan:
- Satu user bisa punya lebih dari satu role jika nanti dibutuhkan.
- Role aktif user tidak disimpan sebagai string tunggal di banyak tempat; role disimpan terpusat.

## Prinsip inti

- Satu sumber data untuk identitas user.
- Satu sumber data untuk role user.
- Satu sumber data untuk hubungan atasan-bawahan.
- Satu sumber data untuk assignment toko.
- Satu sumber data untuk target per periode.
- Tidak ada tabel terpisah per pasangan role seperti `hierarchy_spv_sator`, `hierarchy_sator_promotor`, dan seterusnya.

## Tabel inti

### `app_users`

Data identitas user aplikasi.

Kolom utama:
- `id`
- `auth_user_id`
- `employee_code`
- `full_name`
- `email`
- `phone`
- `status`
- `home_area_id`
- `created_at`
- `updated_at`
- `deleted_at`

Fungsi:
- menyimpan profil user inti
- satu baris per orang

### `app_roles`

Master role.

Kolom utama:
- `code`
- `name`
- `sort_order`
- `is_system`

Fungsi:
- daftar role resmi aplikasi

### `user_role_assignments`

Role yang dimiliki user.

Kolom utama:
- `id`
- `user_id`
- `role_code`
- `is_primary`
- `active`
- `starts_at`
- `ends_at`

Fungsi:
- memungkinkan satu user punya satu atau banyak role
- menentukan role utama yang dipakai dashboard

### `app_areas`

Master area operasi.

Kolom utama:
- `id`
- `code`
- `name`
- `active`

Fungsi:
- acuan area user dan toko

### `app_stores`

Master toko.

Kolom utama:
- `id`
- `code`
- `name`
- `area_id`
- `channel`
- `active`

Fungsi:
- satu sumber data toko

### `user_supervisions`

Hubungan atasan-bawahan generik.

Kolom utama:
- `id`
- `supervisor_user_id`
- `subordinate_user_id`
- `supervisor_role_code`
- `subordinate_role_code`
- `active`
- `starts_at`
- `ends_at`

Fungsi:
- menggantikan semua tabel hierarchy lama
- bisa dipakai untuk:
  - `manager -> spv`
  - `spv -> trainer`
  - `trainer -> sator`
  - `sator -> promotor`
  - atau pola lain nanti

### `store_assignments`

Hubungan user dengan toko.

Kolom utama:
- `id`
- `user_id`
- `store_id`
- `assignment_role_code`
- `active`
- `starts_at`
- `ends_at`

Fungsi:
- promotor pegang toko mana
- sator pegang toko mana
- trainer atau spv bisa juga ditautkan ke toko jika nanti perlu

### `app_target_periods`

Periode target resmi.

Kolom utama:
- `id`
- `period_type`
- `period_name`
- `start_date`
- `end_date`
- `status`

Fungsi:
- satu periode resmi untuk target bulanan
- bisa dikembangkan ke mingguan atau kuartalan

### `app_target_period_weeks`

Pembagian minggu di dalam satu periode target.

Kolom utama:
- `id`
- `period_id`
- `week_number`
- `start_date`
- `end_date`
- `weight_percent`
- `working_days`

Fungsi:
- minggu ke berapa
- tanggal berapa sampai berapa
- bobot target minggu berapa persen
- hari kerja resmi berapa

### `app_user_targets`

Target utama per user per periode.

Kolom utama:
- `id`
- `user_id`
- `period_id`
- `role_code`
- `sell_out_target`
- `sell_in_target`
- `focus_target`
- `new_outlet_target`
- `visit_target`
- `active`

Fungsi:
- satu baris target inti per user per periode
- semua dashboard membaca dari tabel ini

## Alur hitungan target

Rumus dasar yang dipakai:

- `target mingguan = target bulanan x bobot minggu / 100`
- `target harian = target mingguan / working_days`
- `sisa = target harian - actual hari ini`
- `progress = actual hari ini / target harian x 100`

Produk fokus memakai pola yang sama:

- `target fokus mingguan = target fokus bulanan x bobot minggu / 100`
- `target fokus harian = target fokus mingguan / working_days`

## Kenapa schema ini lebih aman

- tidak ada tabel hierarchy per pasangan role
- tidak ada `period_id` palsu dari string bulan-tahun
- tidak ada role string liar tersebar di banyak tabel
- assignment toko dan hierarchy dipisah tegas
- target dan pembagian minggunya dipisah tegas
- trainer bisa dimasukkan tanpa bongkar fondasi
- nambah SPV, SATOR, Promotor baru cukup insert data, tidak perlu bikin tabel baru

## Dampak ke aplikasi

Setelah schema ini dipakai, UI harus ikut disiplin:

- admin user hanya kelola identitas user
- admin hierarchy hanya kelola atasan-bawahan
- admin assignment toko hanya kelola user ke toko
- admin target hanya kelola periode, bobot minggu, dan target
- dashboard Promotor, SATOR, SPV, Trainer membaca angka dari sumber yang sama

## Langkah rebuild yang benar

1. Buat schema inti baru.
2. Isi master role.
3. Isi user.
4. Isi relasi atasan-bawahan.
5. Isi assignment toko.
6. Isi periode target dan minggu aktif.
7. Isi target user.
8. Setelah data inti stabil, baru tulis RPC baru dan sambungkan UI baru.
