# Business Naming Standard

Dokumen ini adalah kamus resmi untuk istilah bisnis, nama field, nama label UI, dan aturan turunan.  
Tujuan utamanya: satu istilah = satu arti = satu nama.

## Aturan umum

- Nama database dan field pakai bahasa Inggris snake_case.
- Nama fungsi/RPC pakai bahasa Inggris snake_case.
- Nama model Dart pakai bahasa Inggris.
- Label UI ke user pakai bahasa Indonesia yang konsisten.
- Satu istilah bisnis tidak boleh punya 2 nama.

## Istilah inti resmi

### 1. `sell_out`

Arti:
- penjualan keluar ke customer
- satuan utama: rupiah

Label UI resmi:
- `Sell Out`

Catatan:
- jangan pakai `Sellout`
- jangan pakai `Sell out`
- jangan pakai `SO`

### 2. `sell_out_all_type`

Arti:
- seluruh nilai sell out dari semua produk
- satuan utama: rupiah

Label UI resmi:
- `Target Sell Out All Type`
- `Realisasi Sell Out All Type`

Singkatan tampilan pendek:
- `All Type`

Catatan:
- jangan campur dengan `omzet` di label utama
- kalau butuh label singkat di kartu, pakai `All Type`

### 3. `focus_product`

Arti:
- produk yang masuk kategori fokus
- satuan utama: unit

Label UI resmi:
- `Produk Fokus`

Catatan:
- jangan pakai `Fokus Produk`
- jangan pakai `Focus Product`
- jangan pakai `Tipe Fokus` sebagai istilah induk

### 4. `sell_out_focus_product`

Arti:
- penjualan produk fokus saja
- satuan utama: unit

Label UI resmi:
- `Target Produk Fokus`
- `Realisasi Produk Fokus`

Singkatan tampilan pendek:
- `Produk Fokus`

### 5. `special_type`

Arti:
- sub-kelompok khusus di dalam produk fokus
- ini turunan dari `Produk Fokus`, bukan domain terpisah

Label UI resmi:
- `Tipe Khusus`

Catatan:
- `Tipe Khusus` berada di bawah `Produk Fokus`
- jangan pakai `Special`
- jangan pakai `Special Case` di UI utama

## Struktur bisnis resmi

Struktur domain target sell out harus selalu begini:

- `Target Sell Out`
- `Target Sell Out All Type`
- `Target Produk Fokus`
- `Detail Tipe Khusus`

Artinya:
- `Target Sell Out` adalah domain induk
- domain induk itu dibagi menjadi 2:
  - `All Type`
  - `Produk Fokus`
- `Produk Fokus` bisa punya detail lagi:
  - `Tipe Khusus`

## Struktur field resmi

### Database

Gunakan nama berikut:

- `sell_out_target`
- `sell_out_actual`
- `sell_out_achievement_pct`
- `sell_out_all_type_target`
- `sell_out_all_type_actual`
- `sell_out_all_type_achievement_pct`
- `focus_product_target`
- `focus_product_actual`
- `focus_product_achievement_pct`
- `special_type_target`
- `special_type_actual`
- `special_type_achievement_pct`

### Harian

- `daily_sell_out_all_type_target`
- `daily_sell_out_all_type_actual`
- `daily_focus_product_target`
- `daily_focus_product_actual`

### Mingguan

- `weekly_sell_out_all_type_target`
- `weekly_sell_out_all_type_actual`
- `weekly_focus_product_target`
- `weekly_focus_product_actual`

### Bulanan

- `monthly_sell_out_all_type_target`
- `monthly_sell_out_all_type_actual`
- `monthly_focus_product_target`
- `monthly_focus_product_actual`

## Label UI resmi

### Kartu target

Selalu pakai urutan ini:

1. `Target`
2. `Realisasi`
3. `Sisa`
4. `Pencapaian`

Jangan pakai campuran:
- `Ach`
- `Progress` di satu layar dan `Pencapaian` di layar lain
- `Capai`

Untuk produk fokus:
- `Target Produk Fokus`
- `Realisasi Produk Fokus`
- `Sisa Produk Fokus`
- `Pencapaian Produk Fokus`

### Tab periode

Hanya boleh:
- `Harian`
- `Mingguan`
- `Bulanan`

Tidak boleh:
- `Hari`
- `Minggu`
- `Bulan`

### Header user

Urutan resmi:
- `Selamat datang,`
- `Nama User`
- chip ketiga sesuai role:
  - Promotor: `Nama Toko`
  - SATOR: `Jabatan`
  - SPV: `Jabatan`
  - Trainer: `Jabatan`
- info kecil di bawah: `Area`

## Nama menu role

Bottom navigation utama harus sama:

- `Home`
- `Workplace`
- `Ranking`
- `Chat`
- `Profil`

Kalau role tertentu butuh menu tambahan, jangan masuk bottom nav utama.  
Masukkan ke `Workplace`.

## Rumus istilah target

Istilah resmi:

- `target bulanan`
- `bobot minggu`
- `target mingguan`
- `hari kerja`
- `target harian`
- `realisasi`
- `sisa`
- `pencapaian`

Rumus resmi:

- `target mingguan = target bulanan x bobot minggu / 100`
- `target harian = target mingguan / hari kerja`
- `sisa = target harian - realisasi`
- `pencapaian = realisasi / target harian x 100`

## Larangan penamaan

Jangan pakai lagi istilah berikut di schema atau UI baru:

- `omzet_target` jika maksudnya `sell_out_all_type_target`
- `target_fokus_total` jika maksudnya `focus_product_target`
- `fokus`
- `focus`
- `special`
- `all_type` di UI user-facing
- `sellout`
- `sell out all`
- `target bulan`
- `nama tab bulan`

## Checklist sebelum merge

Sebelum fitur baru diterima, cek:

- apakah istilah bisnisnya sudah ada di dokumen ini
- apakah field database dan label UI punya arti yang sama
- apakah `Produk Fokus` tidak dipakai sebagai nama domain dan nama sub-item sekaligus
- apakah `Tipe Khusus` hanya muncul sebagai turunan dari `Produk Fokus`
- apakah `Harian/Mingguan/Bulanan` konsisten di semua tempat
