# HANDOVER AGENT - 04 Mar 2026 (AllBrand Update)

## Ringkasan Status
Fokus sesi:
1. Stabilkan flow AllBrand agar aman dari error JSON di database.
2. Pastikan data harian vs akumulasi bisa disimpan dan dibaca jelas.

Status saat handover:
- Kolom baru AllBrand sudah disiapkan di DB user:
  - `brand_data_daily`
  - `leasing_sales_daily`
  - `daily_total_units`
  - `cumulative_total_units`
- Normalisasi data JSON sudah dijalankan user:
  - `brand_data` valid object
  - `brand_data_daily` valid object
- Verifikasi user:
  - `bad_brand_data = 0`
  - `bad_brand_data_daily = 0`
- Query sample user menunjukkan data berjalan:
  - `2026-03-04` -> `daily_total_units=27`, `cumulative_total_units=27`

## Perubahan Kode yang Sudah Dibuat

### 1) Form AllBrand (UI + payload)
File:
- `lib/features/promotor/presentation/pages/laporan_allbrand_page.dart`

Perubahan:
- Tambah helper hitung total:
  - total harian dari input hari ini
  - estimasi akumulasi berjalan
- Saat load data:
  - prioritas baca `brand_data_daily` jika tersedia
  - fallback ke data lama bila perlu
- Saat submit:
  - simpan field lama + field baru (kompatibel)
  - set `daily_total_units` dan `cumulative_total_units`
- Tambah ringkasan di UI:
  - "Input Hari Ini"
  - "Akumulasi (estimasi)"

### 2) SQL migration dan hardening JSON
File:
- `supabase/migrations/20260304_allbrand_daily_and_cumulative.sql`
- `supabase/migrations/20260304_fix_allbrand_jsonb_each_non_object.sql` (baru)
- `supabase/migrations/20260123_allbrand_functions_only.sql`
- `supabase/migrations/20260123_allbrand_system.sql`

Perubahan:
- Tambah kolom harian + total unit.
- Backfill data lama ke format baru.
- Patch `get_allbrand_summary` agar `jsonb_each` hanya dipanggil pada JSON object (aman dari error `22023`).

## Error yang Terjadi dan Root Cause
Error user:
- `ERROR: 22023: cannot call jsonb_each on a non-object`

Root cause:
- Data historis `brand_data` (atau `brand_data_daily`) ada yang bukan JSON object.
- Fungsi summary lama memanggil `jsonb_each(brand_data)` langsung.

Fix:
- Normalisasi data non-object jadi `'{}'::jsonb`.
- Guard `jsonb_typeof(...)='object'` sebelum `jsonb_each`.

## SQL yang Sudah Dijalankan User (Confirmed)
1. `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`
2. Normalisasi:
   - update `brand_data`
   - update `brand_data_daily`
3. Verifikasi:
   - hasil `bad_brand_data=0`, `bad_brand_data_daily=0`

## Pekerjaan Lanjutan Besok (Prioritas)
1. Buat halaman/section "Riwayat Akumulasi Harian" (tanpa perlu SQL manual).
2. Tampilkan agregasi harian yang mudah dibaca atasan:
   - total laporan per hari
   - total unit harian
   - running cumulative per toko/per promotor.
3. Samakan istilah di UI:
   - "Harian" vs "Akumulasi" harus konsisten di card, detail, dan summary.
4. Uji lintas role:
   - promotor input
   - sator/spv membaca laporan tanpa ambigu.

## Catatan Implementasi untuk Agent Berikutnya
- Hindari asumsi semua JSON di tabel lama selalu object.
- Untuk query agregat JSON, selalu gunakan pola:
  - `CASE WHEN jsonb_typeof(col)='object' THEN col ELSE '{}'::jsonb END`
- Jangan hapus field lama dulu (`brand_data`, `leasing_sales`) sampai semua endpoint/layanan dipastikan pindah ke field baru.
