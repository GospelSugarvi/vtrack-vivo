# Cara Testing IMEI Normalization System

## Langkah-Langkah Testing

---

## STEP 1: Jalankan SQL Fix

### 1.1 Buka Supabase Dashboard
1. Buka browser, masuk ke https://supabase.com
2. Login ke project Anda
3. Pilih project vtrack

### 1.2 Buka SQL Editor
1. Di sidebar kiri, klik **SQL Editor**
2. Klik **New query**

### 1.3 Copy & Paste SQL
1. Buka file: `supabase/fix_sator_imei_list_correct.sql`
2. Copy semua isinya (Ctrl+A, Ctrl+C)
3. Paste ke SQL Editor di Supabase (Ctrl+V)

### 1.4 Execute SQL
1. Klik tombol **Run** (atau tekan Ctrl+Enter)
2. Tunggu sampai selesai

### 1.5 Cek Output
Anda harus melihat output seperti ini:
```
NOTICE: === Testing get_sator_imei_list ===
NOTICE: Sator ID: [uuid-sator]
NOTICE: Result count: 0 (atau angka lain)
```

**Jika ada error:**
- Screenshot error
- Kirim ke saya untuk analisa

**Jika success:**
- Lanjut ke Step 2

---

## STEP 2: Restart Flutter App

### 2.1 Stop App
```bash
# Tekan Ctrl+C di terminal yang menjalankan flutter
# Atau stop dari IDE
```

### 2.2 Clean & Rebuild
```bash
flutter clean
flutter pub get
flutter run
```

### 2.3 Tunggu App Running
- Tunggu sampai app terbuka di device/emulator
- Pastikan tidak ada error di console

---

## STEP 3: Test dari Promotor

### 3.1 Login sebagai Promotor
1. Buka app
2. Login dengan akun Promotor
3. Masuk ke menu **Penormalan IMEI**

### 3.2 Cek Tab "Belum Lapor"
**Yang harus terlihat:**
- Tab pertama: "Belum Lapor" dengan icon warning
- Ada badge merah dengan angka (misal: 5)
- Isi tab: Info screen dengan tombol "Lihat & Lapor Unit"

**Screenshot:** Tab pertama

### 3.3 Klik FAB "Lapor IMEI"
1. Klik tombol biru di kanan bawah: **"Lapor IMEI"**

**Yang harus terlihat:**
- Modal muncul dari bawah
- Judul: "Lapor Unit Bermasalah"
- Ada info tanggal range (default 7 hari terakhir)
- Ada tombol "Filter"
- List unit yang belum dilaporkan

**Screenshot:** Modal lapor IMEI

### 3.4 Test Filter Tanggal
1. Klik tombol **"Filter"**
2. Date range picker muncul
3. Pilih tanggal mulai dan akhir
4. Klik "Save" atau "OK"
5. List unit update sesuai tanggal

**Screenshot:** Date picker

### 3.5 Lapor Unit Baru
1. Pilih salah satu unit dari list
2. Klik tombol **"Lapor"**

**Yang harus terlihat:**
- Dialog konfirmasi muncul
- Judul: "Konfirmasi Laporan"
- Detail lengkap:
  - Produk: [nama produk]
  - IMEI: [nomor imei]
  - Tanggal Jual: [tanggal]
- Info: "Unit ini akan dikirim ke Sator..."
- Tombol: "Batal" dan "Ya, Lapor"

**Screenshot:** Dialog konfirmasi

### 3.6 Konfirmasi Lapor
1. Klik **"Ya, Lapor"**

**Yang harus terlihat:**
- Modal tertutup
- Success dialog muncul: "Laporan Terkirim!"
- Message: "Laporan berhasil dikirim ke Sator..."
- Klik "OK"

**Screenshot:** Success dialog

### 3.7 Verifikasi Data Pindah
**Yang harus terlihat:**
- Tab "Belum Lapor": Counter berkurang 1
- Tab "Pending": Counter bertambah 1
- Buka tab "Pending": Unit yang baru dilaporkan ada di sana
- Card menampilkan:
  - Nama produk
  - IMEI (bisa di-copy dengan tap)
  - Status: "Belum Diterima" (orange)
  - Tanggal terjual
  - Tanggal dilaporkan

**Screenshot:** Tab Pending dengan unit baru

### 3.8 Test Lapor Duplikat
1. Klik FAB "Lapor IMEI" lagi
2. Coba lapor unit yang sama (IMEI yang sama)
3. Klik "Lapor"
4. Klik "Ya, Lapor"

**Yang harus terlihat:**
- Dialog "IMEI Sudah Dilaporkan" muncul
- Menampilkan:
  - "IMEI ini sudah dilaporkan pada: [tanggal jam]"
  - "Status saat ini: Belum Diterima Sator"
  - Info: "Laporan sedang diproses oleh Sator. Mohon tunggu."
- Tombol "OK"

**Screenshot:** Dialog duplikasi

### 3.9 Test Pull to Refresh
1. Di tab "Pending"
2. Swipe down (tarik ke bawah)
3. Loading indicator muncul
4. Data refresh

**Screenshot:** Pull to refresh

---

## STEP 4: Test dari Sator

### 4.1 Login sebagai Sator
1. Logout dari Promotor
2. Login dengan akun Sator
3. Masuk ke menu **Penormalan IMEI**

### 4.2 Cek Tab "⏳ Baru"
**Yang harus terlihat:**
- Tab "⏳ Baru" ada counter (misal: 1)
- Buka tab tersebut
- Ada IMEI yang dilaporkan Promotor tadi
- Card menampilkan:
  - Nama Promotor
  - Nama Toko
  - IMEI
  - Nama Produk
  - Status: "pending" (orange)

**Screenshot:** Tab Baru di Sator

**❌ Jika TIDAK ADA DATA:**
Kemungkinan masalah:
1. Sator tidak punya store assignment
2. RPC function belum jalan

**Cek Store Assignment:**
```sql
-- Di Supabase SQL Editor
SELECT 
  u.full_name as sator_name,
  s.store_name,
  ssa.is_active
FROM sator_store_assignments ssa
JOIN users u ON ssa.sator_id = u.id
JOIN stores s ON ssa.store_id = s.id
WHERE u.email = '[email-sator-anda]';
```

Jika tidak ada data, berarti Sator belum di-assign ke store.

### 4.3 Test Selection Mode
1. Long press pada card IMEI
2. Card ter-highlight dengan border coklat
3. Checkbox muncul
4. Bottom sheet muncul dengan tombol: Copy, Terima

**Screenshot:** Selection mode

### 4.4 Test Terima IMEI
1. Pastikan IMEI ter-select
2. Klik tombol **"Terima"** di bottom sheet

**Yang harus terlihat:**
- Loading sebentar
- Snackbar: "Berhasil update status ke sent"
- IMEI pindah dari tab "⏳ Baru" ke tab "📥 Diterima"
- Counter update

**Screenshot:** Tab Diterima

### 4.5 Test Normal IMEI
1. Buka tab "📥 Diterima"
2. Long press IMEI yang tadi
3. Klik tombol **"Normal"** di bottom sheet

**Yang harus terlihat:**
- Loading sebentar
- Snackbar: "Berhasil update status ke normalized"
- IMEI pindah ke tab "✅ Normal"
- Counter update

**Screenshot:** Tab Normal

### 4.6 Test Copy IMEI
1. Select beberapa IMEI (long press, tap, tap)
2. Klik tombol **"Copy"**

**Yang harus terlihat:**
- Snackbar: "[X] IMEI disalin ke clipboard"
- Paste di notepad untuk verifikasi

---

## STEP 5: Test Kembali dari Promotor

### 5.1 Login Kembali sebagai Promotor
1. Logout dari Sator
2. Login dengan akun Promotor
3. Masuk ke menu **Penormalan IMEI**

### 5.2 Cek Tab "Normal"
**Yang harus terlihat:**
- Tab "Normal" ada counter (1)
- Buka tab tersebut
- Ada IMEI yang tadi dinormalkan Sator
- Status: "Normal" (hijau)
- Ada tombol: **"Sudah Scan di App Utama"**

**Screenshot:** Tab Normal di Promotor

### 5.3 Test Sudah Scan
1. Klik tombol **"Sudah Scan di App Utama"**

**Yang harus terlihat:**
- Success dialog: "Berhasil! IMEI berhasil ditandai sudah scan!"
- IMEI pindah ke tab "Selesai"
- Counter update

**Screenshot:** Tab Selesai

---

## STEP 6: Verifikasi Data di Database

### 6.1 Cek Tabel imei_normalizations
```sql
-- Di Supabase SQL Editor
SELECT 
  id,
  imei,
  status,
  sold_at,
  created_at,
  sent_to_sator_at,
  normalized_at,
  scanned_at
FROM imei_normalizations
ORDER BY created_at DESC
LIMIT 10;
```

**Yang harus terlihat:**
- IMEI yang baru dilaporkan ada
- Status: 'scanned'
- Semua timestamp terisi:
  - sold_at
  - created_at
  - sent_to_sator_at (NULL - karena tidak ada step kirim manual)
  - normalized_at
  - scanned_at

**Screenshot:** Query result

---

## CHECKLIST TESTING

### ✅ SQL Fix
- [ ] SQL berhasil dijalankan tanpa error
- [ ] Test output menampilkan Sator ID
- [ ] Function exists di database

### ✅ Promotor - Tab & Counter
- [ ] Tab "Belum Lapor" tampil dengan badge merah
- [ ] Counter menampilkan angka yang benar
- [ ] Tab Pending, Diterima, Normal, Selesai tampil

### ✅ Promotor - Modal Lapor
- [ ] Modal muncul dengan list unit
- [ ] Hanya tampilkan unit belum dilaporkan
- [ ] Filter tanggal berfungsi
- [ ] Date picker muncul dan bisa dipilih

### ✅ Promotor - Konfirmasi & Submit
- [ ] Dialog konfirmasi tampil dengan detail lengkap
- [ ] Success dialog tampil setelah submit
- [ ] Unit pindah ke tab Pending
- [ ] Counter update otomatis

### ✅ Promotor - Duplikasi
- [ ] Dialog "IMEI Sudah Dilaporkan" tampil
- [ ] Menampilkan tanggal & status
- [ ] Tidak bisa lapor ulang

### ✅ Promotor - UI/UX
- [ ] Copy IMEI berfungsi (tap pada IMEI)
- [ ] Pull to refresh berfungsi
- [ ] Tidak ada error di console

### ✅ Sator - Tab & Data
- [ ] Tab "⏳ Baru" menampilkan IMEI pending
- [ ] Data lengkap: Promotor, Toko, IMEI, Produk
- [ ] Counter benar

### ✅ Sator - Selection & Action
- [ ] Long press untuk select berfungsi
- [ ] Bottom sheet muncul dengan tombol
- [ ] Tombol "Terima" hanya untuk pending
- [ ] Tombol "Normal" hanya untuk sent

### ✅ Sator - Update Status
- [ ] Terima: Status jadi 'sent', pindah tab
- [ ] Normal: Status jadi 'normalized', pindah tab
- [ ] Copy IMEI berfungsi

### ✅ Integration
- [ ] Promotor lapor → Sator lihat
- [ ] Sator terima → Promotor update
- [ ] Sator normal → Promotor update
- [ ] Promotor scan → Status scanned
- [ ] Tidak ada duplikasi data

### ✅ Database
- [ ] Data tersimpan dengan benar
- [ ] Timestamp terisi semua
- [ ] Status sesuai flow

---

## TROUBLESHOOTING

### Problem: Sator tidak melihat IMEI

**Solusi 1: Cek Store Assignment**
```sql
SELECT * FROM sator_store_assignments 
WHERE sator_id = '[SATOR_USER_ID]' 
AND is_active = true;
```

Jika kosong, insert data:
```sql
INSERT INTO sator_store_assignments (sator_id, store_id, is_active)
VALUES ('[SATOR_USER_ID]', '[STORE_ID]', true);
```

**Solusi 2: Test RPC Manual**
```sql
SELECT get_sator_imei_list('[SATOR_USER_ID]');
```

### Problem: Error saat Lapor

**Cek Console:**
- Buka Flutter console
- Lihat error message
- Biasanya masalah: store_id null

**Cek Data Sales:**
```sql
SELECT id, serial_imei, store_id 
FROM sales_sell_out 
WHERE promotor_id = '[PROMOTOR_USER_ID]'
AND store_id IS NULL;
```

### Problem: Counter Tidak Update

**Solusi:**
- Pull to refresh
- Restart app
- Cek query di `_loadUnreportedCount()`

---

## VIDEO RECORDING (Opsional)

Untuk dokumentasi, Anda bisa record screen:
1. Start recording
2. Ikuti semua step di atas
3. Stop recording
4. Review video untuk memastikan semua berfungsi

---

## HASIL TESTING

Setelah selesai testing, isi form ini:

**Tanggal Testing:** ___________
**Tester:** ___________

**Status:**
- [ ] ✅ Semua test PASSED
- [ ] ⚠️ Ada warning/issue minor
- [ ] ❌ Ada error/issue major

**Issue yang Ditemukan:**
1. ___________
2. ___________

**Screenshot/Video:**
- Attach di folder: `testing_results/`

---

**Selamat Testing!** 🚀

Jika ada masalah, screenshot error dan kirim ke saya untuk analisa.
