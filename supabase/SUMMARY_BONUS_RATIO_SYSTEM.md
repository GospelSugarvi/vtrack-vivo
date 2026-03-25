# 📋 SUMMARY: Bonus Ratio 2:1 System

## ✅ Yang Sudah Ada

### 1. **Database Structure**
- ✅ Tabel `bonus_rules` dengan kolom:
  - `bonus_type` (range/flat/ratio)
  - `ratio_value` (default 2 untuk ratio 2:1)
  - `bonus_official` (bonus untuk promotor official)
  - `bonus_training` (bonus untuk promotor training)
  - `product_id` (link ke products table)

### 2. **Admin UI** (`admin_bonus_page.dart`)
- ✅ Tab "Promotor" dengan 3 section:
  - Range Bonus
  - Flat Bonus
  - **Rasio 2:1** ← Section khusus untuk produk ratio
- ✅ Dialog untuk tambah produk ratio:
  - Pilih produk (dropdown)
  - Input ratio value (default 2)
  - Input bonus official (Rp)
  - Input bonus training (Rp)
- ✅ Dialog untuk edit produk ratio
- ✅ Tombol delete untuk hapus produk ratio

### 3. **Trigger Function** (`process_sell_out_insert`)
- ✅ Logic PRIORITY 2: Cek ratio bonus
- ✅ Hitung cumulative sales bulan ini
- ✅ Logic: Unit ke-2, 4, 6, 8 dapat bonus
- ✅ Unit ke-1, 3, 5, 7 tidak dapat bonus

## ⚠️ Masalah yang Ditemukan

### 1. **Data Inconsistency**
- ❌ Produk Y04S di tabel `products` punya `ratio_val = 1` (seharusnya 2)
- ❌ Belum ada data di tabel `bonus_rules` untuk Y02, Y03T, Y04S

### 2. **Possible Confusion**
- Ada kolom bonus di tabel `products` (bonus_type, ratio_val, flat_bonus)
- Ada tabel terpisah `bonus_rules`
- Function `process_sell_out_insert` membaca dari `bonus_rules`, bukan `products`

## 🔧 Yang Perlu Diperbaiki

### 1. **Update Y04S ratio_val**
```sql
UPDATE products
SET ratio_val = 2
WHERE model_name = 'Y04S' AND bonus_type = 'ratio';
```

### 2. **Tambah data ke bonus_rules**
Admin perlu tambah produk Y02, Y03T, Y04S ke bonus_rules via UI:
- Buka Admin Dashboard → Bonus & Reward
- Tab "Promotor" → Section "Rasio 2:1"
- Klik tombol "+" (Tambah)
- Pilih "Rasio 2:1"
- Isi form:
  - Produk: Y02 / Y03T / Y04S
  - Rasio: 2 (untuk 2:1)
  - Bonus Official: Rp 5.000
  - Bonus Training: Rp 4.000

### 3. **Recalculate existing sales** (optional)
Jika ada sales Y02/Y03T/Y04S yang sudah ada, perlu recalculate bonus-nya.

## 📊 Cara Kerja Sistem

### Flow Perhitungan Bonus Ratio 2:1

```
Promotor jual Y02:

Unit 1 (Januari):
├─ Cek sales Y02 bulan ini: 0 unit
├─ Total sekarang: 1 unit
├─ 1 % 2 = 1 (bukan kelipatan 2)
└─ Bonus: Rp 0 ❌

Unit 2 (Januari):
├─ Cek sales Y02 bulan ini: 1 unit
├─ Total sekarang: 2 unit
├─ 2 % 2 = 0 (kelipatan 2!)
└─ Bonus: Rp 5.000 ✅

Unit 3 (Januari):
├─ Cek sales Y02 bulan ini: 2 unit
├─ Total sekarang: 3 unit
├─ 3 % 2 = 1 (bukan kelipatan 2)
└─ Bonus: Rp 0 ❌

Unit 4 (Januari):
├─ Cek sales Y02 bulan ini: 3 unit
├─ Total sekarang: 4 unit
├─ 4 % 2 = 0 (kelipatan 2!)
└─ Bonus: Rp 5.000 ✅

Total 4 unit = 2 bonus = Rp 10.000
```

### Reset Setiap Bulan
- Counter reset setiap awal bulan
- Februari mulai dari 0 lagi

## 🎯 Action Items

1. ✅ Jalankan `fix_y04s_ratio_value.sql` untuk update ratio_val
2. ✅ Jalankan `fix_bonus_calculation_use_products_table.sql` untuk update function
3. ⚠️ **Admin harus tambah Y02, Y03T, Y04S ke bonus_rules via UI**
4. ✅ Test dengan simulasi penjualan
5. ✅ Verifikasi dengan `test_bonus_ratio_2_1.sql`

## 📝 Notes

- Sistem sudah siap, hanya perlu data di `bonus_rules`
- Admin UI sudah lengkap dan mudah digunakan
- Function trigger sudah benar
- Dokumentasi lengkap ada di `docs/02_LOGIC_BONUS_TARGETS.md`
