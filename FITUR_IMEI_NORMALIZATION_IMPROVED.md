# Fitur IMEI Normalization - Versi Improved

## Perubahan & Fitur Baru

### 1. ✅ Tab "Belum Lapor" (Tab Pertama)
**Fitur:**
- Menampilkan jumlah unit yang gagal scan tapi belum dilaporkan
- Badge merah dengan counter di icon tab
- Info screen dengan tombol "Lihat & Lapor Unit"
- Auto refresh setelah lapor

**Manfaat:**
- User langsung tahu ada berapa unit yang perlu dilaporkan
- Tidak perlu bingung mana yang sudah/belum dilaporkan

### 2. ✅ Modal Lapor IMEI - Hanya Tampilkan Belum Dilaporkan
**Fitur:**
- Hanya menampilkan unit yang **belum pernah dilaporkan**
- Filter berdasarkan tanggal dengan date range picker
- Default: 7 hari terakhir
- Bisa pilih range hingga 90 hari ke belakang

**Manfaat:**
- User tidak bingung melihat unit yang sudah dilaporkan
- Bisa fokus pada unit yang memang perlu dilaporkan
- Fleksibel filter berdasarkan periode

### 3. ✅ Dialog Konfirmasi Sebelum Lapor
**Fitur:**
- Menampilkan detail lengkap unit yang akan dilaporkan:
  - Nama produk (model, RAM/ROM, warna)
  - IMEI
  - Tanggal jual
- Informasi bahwa unit akan dikirim ke Sator
- Tombol "Batal" dan "Ya, Lapor"

**Manfaat:**
- User bisa review sebelum submit
- Menghindari salah lapor
- Lebih profesional

### 4. ✅ Notifikasi IMEI Sudah Dilaporkan
**Fitur:**
- Jika IMEI sudah pernah dilaporkan, tampilkan dialog:
  - Tanggal & jam laporan sebelumnya
  - Status terakhir (Pending/Diterima/Normal/Selesai)
  - Pesan sesuai status:
    - Pending/Sent: "Laporan sedang diproses oleh Sator. Mohon tunggu."
    - Normalized: "IMEI sudah normal. Silakan scan di App Utama."
    - Scanned: "Proses sudah selesai."
- Tidak bisa lapor ulang jika masih dalam proses

**Manfaat:**
- User tahu status terkini IMEI
- Tidak ada duplikasi laporan
- Jelas kapan dilaporkan dan statusnya apa

### 5. ✅ Pengelompokan Status yang Jelas
**5 Tab dengan Counter:**
1. **Belum Lapor** (badge merah) - Unit gagal scan belum dilaporkan
2. **Pending** (orange) - Sudah dilaporkan, belum diterima Sator
3. **Diterima** (biru) - Sudah diterima Sator, sedang diproses
4. **Normal** (hijau) - Sudah normal, siap scan ulang
5. **Selesai** (ungu) - Sudah scan ulang, proses selesai

**Manfaat:**
- User langsung tahu ada berapa unit di setiap tahap
- Tidak bingung status unit
- Mudah tracking progress

### 6. ✅ Informasi Lengkap di Card IMEI
**Ditampilkan:**
- Nama produk lengkap
- IMEI (bisa di-copy dengan tap)
- Status dengan warna & icon
- Tanggal terjual
- Tanggal dilaporkan
- Tombol aksi sesuai status

**Manfaat:**
- Semua info penting ada di satu tempat
- Mudah copy IMEI jika perlu
- Jelas kapan terjual dan kapan dilaporkan

### 7. ✅ Pull to Refresh
**Fitur:**
- Swipe down untuk refresh data
- Auto update counter di semua tab

**Manfaat:**
- Selalu dapat data terbaru
- Tidak perlu keluar-masuk halaman

## Flow Penggunaan

### Skenario 1: Lapor Unit Baru
1. User buka halaman "Penormalan IMEI"
2. Lihat tab "Belum Lapor" ada badge merah (misal: 5 unit)
3. Klik FAB "Lapor IMEI" atau tombol di tab pertama
4. Modal muncul dengan list 5 unit yang belum dilaporkan
5. Bisa filter tanggal jika perlu
6. Klik "Lapor" pada unit yang bermasalah
7. Dialog konfirmasi muncul dengan detail lengkap
8. Klik "Ya, Lapor"
9. Success dialog: "Laporan terkirim ke Sator"
10. Unit pindah ke tab "Pending"
11. Badge "Belum Lapor" berkurang jadi 4

### Skenario 2: Coba Lapor Unit yang Sudah Dilaporkan
1. User klik "Lapor IMEI"
2. Pilih unit (tapi ternyata sudah pernah dilaporkan)
3. Klik "Lapor"
4. Dialog konfirmasi muncul
5. Klik "Ya, Lapor"
6. Dialog muncul: "IMEI Sudah Dilaporkan"
   - Dilaporkan pada: 05 Mar 2026 14:30
   - Status: Diterima Sator
   - "Laporan sedang diproses oleh Sator. Mohon tunggu."
7. User klik "OK"
8. Tidak ada duplikasi laporan

### Skenario 3: Cek Status Unit
1. User buka tab "Diterima" (3 unit)
2. Lihat list 3 unit yang sedang diproses Sator
3. Pull down untuk refresh
4. 1 unit sudah pindah ke tab "Normal"
5. Tab "Diterima" sekarang (2 unit)
6. Tab "Normal" sekarang (1 unit)

### Skenario 4: Scan Ulang Unit Normal
1. User buka tab "Normal"
2. Lihat unit yang sudah dinormalkan Sator
3. Klik tombol "Sudah Scan di App Utama"
4. Success dialog muncul
5. Unit pindah ke tab "Selesai"

## Perbedaan dengan Versi Lama

| Aspek | Versi Lama | Versi Baru |
|-------|-----------|-----------|
| Modal Lapor | Tampilkan 20 penjualan terakhir | Hanya yang belum dilaporkan |
| Filter Tanggal | Tidak ada | Ada (date range picker) |
| Konfirmasi | Langsung submit | Dialog konfirmasi detail |
| Duplikasi | Bisa terjadi | Dicegah dengan notifikasi |
| Tab | 4 tab | 5 tab (+ Belum Lapor) |
| Counter | Ada | Ada + badge merah |
| Info Tanggal | Hanya tanggal jual | Tanggal jual + dilaporkan |
| Status Text | Kurang jelas | Sangat jelas |

## Keuntungan untuk User

1. **Tidak Bingung** - Jelas mana yang perlu dilaporkan
2. **Tidak Duplikasi** - Sistem cegah lapor ulang
3. **Tracking Jelas** - Tahu status setiap unit
4. **Efisien** - Filter tanggal, pull refresh
5. **Aman** - Konfirmasi sebelum submit
6. **Informatif** - Notifikasi lengkap dengan detail

## Technical Notes

### Query Optimization
- Menggunakan `NOT IN` untuk filter IMEI yang sudah dilaporkan
- Index pada kolom `imei` dan `promotor_id` untuk performa
- Limit query untuk menghindari load berlebihan

### State Management
- Auto refresh setelah lapor
- Update counter di semua tab
- Sinkronisasi data real-time

### Error Handling
- Validasi store_id sebelum insert
- Catch error dengan pesan yang jelas
- Debug print untuk troubleshooting

## Testing Checklist

- [ ] Tab "Belum Lapor" menampilkan counter yang benar
- [ ] Modal hanya tampilkan unit yang belum dilaporkan
- [ ] Filter tanggal berfungsi dengan baik
- [ ] Dialog konfirmasi tampil dengan data lengkap
- [ ] Notifikasi duplikasi tampil jika IMEI sudah dilaporkan
- [ ] Unit pindah tab sesuai status
- [ ] Pull to refresh update data
- [ ] Copy IMEI berfungsi
- [ ] Tombol "Sudah Scan" hanya muncul di status Normal
- [ ] Success dialog tampil setelah submit
- [ ] Badge merah update setelah lapor

## Next Steps

1. Jalankan SQL fix: `supabase/fix_sator_imei_list_correct.sql`
2. Test flow lengkap dari Promotor
3. Test flow lengkap dari Sator
4. Verifikasi tidak ada duplikasi data
5. Monitor performa query
