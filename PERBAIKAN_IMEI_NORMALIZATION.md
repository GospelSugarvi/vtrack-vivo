# Perbaikan IMEI Normalization System

## Masalah yang Ditemukan

### 1. RPC Function Salah Kolom
**Masalah:** 
- Function `get_sator_imei_list` menggunakan kolom `new_imei` dan `old_imei` yang tidak ada di tabel
- Function menggunakan `s.name` padahal kolom yang benar adalah `s.store_name`

**Tabel sebenarnya:** `imei_normalizations` hanya punya kolom `imei`

**Dampak:** Sator tidak bisa melihat IMEI yang dilaporkan Promotor

**Solusi:** Jalankan file SQL `supabase/fix_sator_imei_list_correct.sql`

### 2. Status Tidak Konsisten
**Masalah:** 
- Database constraint: `'pending', 'sent', 'normalized', 'scanned'`
- Kode menggunakan: `'normal'` (salah!)

**Dampak:** Update status gagal karena constraint violation

**Solusi:** Sudah diperbaiki di kode Flutter, gunakan `'normalized'` bukan `'normal'`

### 3. Kemungkinan Masalah Store Assignment
**Potensi masalah:** Sator mungkin belum di-assign ke store Promotor

**Cek:** Pastikan ada data di tabel `sator_store_assignments` yang menghubungkan Sator dengan Store

## File yang Sudah Diperbaiki

### Flutter Code:
1. `lib/features/sator/presentation/pages/imei_normalisasi_page.dart`
   - Status 'normal' → 'normalized'
   - Label lebih jelas

2. `lib/features/promotor/presentation/pages/imei_normalization_page.dart`
   - Status 'normal' → 'normalized'
   - Hapus logic ganda untuk normal/normalized

### SQL Fix:
1. `supabase/fix_sator_imei_list_correct.sql` (BARU)
   - Perbaiki kolom dari `new_imei`/`old_imei` → `imei`
   - Tambah test untuk debugging

## Langkah Perbaikan

### 1. Jalankan SQL Fix
```bash
# Di Supabase SQL Editor, jalankan:
supabase/fix_sator_imei_list_correct.sql
```

### 2. Cek Store Assignment
```sql
-- Cek apakah Sator punya assignment ke store
SELECT 
  u.full_name as sator_name,
  s.name as store_name,
  ssa.is_active
FROM sator_store_assignments ssa
JOIN users u ON ssa.sator_id = u.id
JOIN stores s ON ssa.store_id = s.id
WHERE u.role = 'sator'
ORDER BY u.full_name, s.name;
```

### 3. Test Flow
1. Login sebagai Promotor
2. Klik "Lapor IMEI" 
3. Pilih unit dari list
4. Klik "Lapor"
5. Cek apakah muncul di tab "Belum" (status pending)
6. Login sebagai Sator
7. Cek apakah IMEI muncul di tab "⏳ Baru"
8. Pilih IMEI, klik "Terima" → status jadi 'sent'
9. Pilih lagi, klik "Normal" → status jadi 'normalized'
10. Login kembali sebagai Promotor
11. Cek tab "Normal", klik "Sudah Scan" → status jadi 'scanned'

## Status Flow yang Benar

```
Promotor lapor → pending (Belum Diterima)
       ↓
Sator klik "Terima" → sent (Diterima Sator)
       ↓
Sator klik "Normal" → normalized (Normal)
       ↓
Promotor klik "Sudah Scan" → scanned (Selesai)
```

## Debug Tips

Jika masih tidak muncul di Sator, cek:

1. **Apakah insert berhasil?**
```sql
SELECT * FROM imei_normalizations 
ORDER BY created_at DESC 
LIMIT 10;
```

2. **Apakah Sator punya store assignment?**
```sql
SELECT * FROM sator_store_assignments 
WHERE sator_id = '[SATOR_USER_ID]' 
AND is_active = true;
```

3. **Apakah RPC function sudah benar?**
```sql
-- Test manual
SELECT get_sator_imei_list('[SATOR_USER_ID]');
```

4. **Cek error di Flutter console** saat Promotor klik "Lapor"
