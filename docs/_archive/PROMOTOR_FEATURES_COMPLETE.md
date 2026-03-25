# 📋 ANALISIS LENGKAP: FITUR & PEKERJAAN PROMOTOR

**Berdasarkan:** Sistem yang sudah ada (Django)  
**Tujuan:** Dokumentasi untuk rebuild Flutter app  
**Tanggal:** 2 Januari 2026

---

## 🎯 OVERVIEW: APA YANG PROMOTOR LAKUKAN?

Promotor adalah **front-line sales** di toko retail yang bertugas:
1. Jual produk VIVO
2. Catat penjualan & stok
3. Laporkan aktivitas harian
4. Handle customer kredit
5. Promosi di sosial media

**Total User:** ±35 promotor di berbagai toko

---

## 📱 HALAMAN & FITUR PROMOTOR (Dari Sistem Lama)

### **1. DASHBOARD / HOME** 
**File:** `dashboard_landing_page`, `sell_out_dashboard`

**Apa yang dilihat:**
- Total penjualan hari ini
- Total bonus hari ini  
- Achievement vs target (%)
- Recent activities (penjualan terakhir)
- Quick actions buttons

**Apa yang bisa diklik:**
- Tombol "Input Jualan" → ke form penjualan
- Tombol "Input Stok" → ke form stok
- Tombol "Clock In" → ke absensi
- Tombol "Lihat Bonus" → ke halaman bonus detail

**Data yang ditampilkan:**
- Jumlah unit terjual
- Total omzet rupiah
- Bonus earned
- Target achievement percentage
- Breakdown per produk

---

### **2. INPUT PENJUALAN (JUALAN)**
**File:** `laporan_jual_form`, `laporan_jual_fresh`  
**URL:** `/promotor/laporan/jual/`

#### **Yang harus promotor isi:**

**Step 1: Data Produk**
- **IMEI** (15 digit)
  - Bisa scan barcode
  - Atau ketik manual
  - System auto-detect produk dari IMEI
  - Validasi: wajib unique (tidak boleh duplikat)

**Step 2: Detail Penjualan**
- **Harga Jual** (angka rupiah)
  - Validasi: harus >= harga modal
  - Default: SRP dari database
  
- **Jenis Barang** (dropdown)
  - Fresh (produk baru)
  - Chip (second/bekas)
  - Cuci Gudang (clearance)
  
- **Jenis Pembayaran** (dropdown)
  - Cash
  - Kredit (kalau kredit → tanya leasing company)
  
- **Jenis User** (dropdown)
  - Customer Toko (walk-in)
  - Customer Janjian (appointment)
  
- **Jenis Leasing** (dropdown, kalau kredit)
  - HCI
  - Kredivo
  - Indodana
  - FIF
  - Lainnya

**Step 3: Data Customer (Optional)**
- **Foto Customer** (upload image)
  - Via camera
  - Validasi: ukuran max 5MB
  
- **No. Telepon Customer** (opsional)
  - 10-13 digit
  
- **Catatan** (text area)
  - Keterangan tambahan

#### **Yang terjadi setelah submit:**

1. **Validasi:**
   - IMEI tidak boleh duplikat
   - Semua field required harus terisi
   - Format data harus benar

2. **Simpan ke database:**
   - Tabel `jualan`
   - Generate bonus otomatis ke `bonus_harian`
   
3. **Upload foto** (kalau ada):
   - Ke Cloudinary
   - Compress image dulu
   
4. **Kirim notifikasi Discord:**
   - Ke channel tim (NIO atau ANDRI)
   - Ke channel public
   - Format: embed dengan detail penjualan
   
5. **Show success message:**
   - "Penjualan berhasil dicatat!"
   - "Bonus Anda: Rp XXX"
   - Redirect ke dashboard

6. **Kalau error:**
   - Show error message
   - Jangan hapus data form
   - User bisa perbaiki & re-submit

---

### **3. INPUT STOK**
**File:** `laporan_stok_form`  
**URL:** `/promotor/laporan/stok/`

#### **Ada 3 jenis input stok:**

#### **A. Stok Baru Masuk**

**Yang harus diisi:**
- **IMEI** (scan atau ketik)
  - Auto-detect produk
  - Validasi: unique, belum ada di DB
  
- **Tipe Stok** (dropdown)
  - **Display** = Produk untuk display di toko
  - **Ready** = Produk siap jual
  - **Transit** = Produk dalam perjalanan ke toko
  
- **Foto Produk** (optional)
  - Screenshot nota
  - Foto box produk

**Yang terjadi:**
- Simpan ke tabel `stok`
- Notifikasi Discord ke channel stok
- Update inventory count

#### **B. Produk Tidak Ada / Kosong**

**Digunakan saat:** Stok display/ready habis

**Yang harus diisi:**
- **Pilih produk yang habis** (dropdown dari list)
- **Jumlah yang dibutuhkan** (angka)
- **Catatan/Alasan** (text)

**Yang terjadi:**
- Trigger notifikasi ke SATOR
- Masuk recommendation order
- Priority untuk restocking

#### **C. Cuci Gudang (Clearance)**

**Digunakan saat:** Ada produk sale/discount

**Yang harus diisi:**
- **Nama Model** (text)
- **Varian RAM/ROM** (text)
- **Warna** (text)
- **Harga Khusus** (angka, lebih murah dari SRP)
- **IMEI** (unique)

**Yang terjadi:**
- Simpan ke tabel `cuci_gudang`
- Terpisah dari stok normal
- Bisa di-track khusus

---

### **4. ABSENSI (CLOCK IN)**
**File:** `absensi_form`, `absensi_fresh`, `clock_in_api`  
**URL:** `/promotor/absensi/`

#### **Yang harus promotor lakukan:**

**Step 1: Buka halaman absensi**
- System cek: sudah clock in hari ini?
- Kalau sudah → show "Anda sudah clock in"
- Kalau belum → show form

**Step 2: Ambil foto selfie**
- Kamera langsung aktif
- Foto wajah promotor
- Validasi: wajib ada foto

**Step 3: GPS auto-detect** (otomatis)
- System ambil lokasi GPS
- Simpan latitude & longitude
- Kalau GPS off → tetap bisa submit (tapi warning)

**Step 4: Submit**

**Yang terjadi:**
1. Upload foto ke Cloudinary (folder: absensi)
2. Simpan ke tabel `absensi`:
   - pengguna_id
   - foto_path
   - latitude, longitude
   - waktu_clock_in (WITA timezone)
3. Kirim notifikasi Discord:
   - Ke channel absensi tim
   - Include foto & lokasi map link
4. Success message: "Clock in berhasil!"

#### **Business Rules:**
- **Satu kali per hari** (tidak bisa clock in 2x)
- **Foto wajib** (tidak boleh kosong)
- **GPS opsional** (tapi recommended)
- **Waktu:** Pakai WITA (Asia/Makassar timezone)

---

### **5. BONUS & ACHIEVEMENT**
**File:** `bonus_promotor_view`, `dashboard_views` (bonus part)  
**URL:** `/promotor/dashboard/bonus/`

#### **Yang ditampilkan:**

**A. Total Bonus Hari Ini**
```
💰 Rp 750,000
↗ +15% dari kemarin
```

**B. Breakdown Bonus per Produk**
```
Table:
┌──────────────┬──────┬────────┬──────────┐
│ Produk       │ Unit │ Bonus  │ Subtotal │
├──────────────┼──────┼────────┼──────────┤
│ Y19s 8/128   │  5   │ 150k   │  750k    │
│ V40 12/256   │  3   │ 250k   │  750k    │
│ Y400 6/128   │  7   │ 100k   │  700k    │
└──────────────┴──────┴────────┴──────────┘
TOTAL: Rp 2,200,000
```

**C. Achievement Progress**
```
🎯 Target Unit Fokus
████████░░ 75% (15/20 unit)

💰 Target Omzet
███████░░░ 70% (35jt/50jt)

💳 Target VAST Finance
██████░░░░ 60% (6/10 aplikasi)
```

**D. Filter Periode**
```
Dropdown:
- Hari Ini
- Minggu Ini (Week 1-4)
- Bulan Ini
- Custom (pilih range tanggal)
```

#### **Special Logic: "2 Hitung 1"**

**Produk tertentu** (Y03t, Y04s, Y02) punya aturan khusus:
- Jual 2 unit → dihitung 1 unit untuk bonus
- Jual 4 unit → bonus 2 unit
- Jual 3 unit → bonus 1 unit (yang 1 hilang)

**Contoh:**
```
Promotor jual Y03t sebanyak 4 unit
Bonus per unit: Rp 100,000

Perhitungan:
- Actual sales: 4 unit
- Counted sales: 4 ÷ 2 = 2 unit
- Bonus earned: 2 × 100k = Rp 200,000

Di tabel breakdown:
"Y03t (4 unit) → Rp 200,000 ⚠️ (2=1 rule)"
```

---

### **6. PROMOSI MEDIA SOSIAL**
**File:** `laporan_promosi_form`  
**URL:** `/promotor/laporan/promosi/`

#### **Yang harus diisi:**

**Per Platform (bisa multiple):**

**Platform Options:**
- TikTok
- Instagram  
- Facebook
- WhatsApp
- YouTube
- Lainnya

**Untuk setiap platform:**
1. **Pilih platform** (dropdown)
2. **Upload screenshot** (multiple images OK)
   - Bukti posting
   - Max 5MB per foto
   - Wajib minimal 1 foto
3. **Catatan** (text area, opsional)
   - Deskripsi konten
   - Engagement rate
   - Keterangan lain

**Tombol:**
- **[+ Tambah Platform]** → untuk report multiple platform
- **[Hapus]** → untuk hapus platform entry

**Contoh input:**
```
Platform: TikTok
Screenshot: [foto1.jpg] [foto2.jpg]
Catatan: "Video unboxing Y19s, 1.2k views"

Platform: Instagram
Screenshot: [foto3.jpg]
Catatan: "Story produk, 500+ impressions"
```

#### **Yang terjadi setelah submit:**

1. **Validasi:**
   - Minimal 1 platform harus diisi
   - Setiap platform wajib ada foto
   - Foto tidak boleh duplikat (check hash)

2. **Upload:**
   - Semua foto ke Cloudinary (folder: promosi_medsos)
   - Generate MD5 hash untuk detect duplicate

3. **Simpan database:**
   - Header: tabel `promosi_medsos`
   - Detail: tabel `promosi_medsos_detail` (per platform)
   
4. **Notifikasi Discord:**
   - Ke channel promosi tim
   - Summary: "5 foto promosi di 2 platform"
   - Attach foto pertama sebagai thumbnail
   
5. **Success:**
   - Message: "Laporan promosi berhasil!"
   - Redirect ke dashboard

---

### **7. PENGAJUAN KREDIT VAST FINANCE**
**File:** `laporan_vast_finance_form`, `vast_finance_dashboard`  
**URL:** `/promotor/laporan/vast_finance/`

#### **Form Input Pengajuan:**

**Data Customer:**
- **Nama Pemohon** (text)
- **No. Telepon** (10-13 digit)
- **Pekerjaan** (text)
- **Penghasilan Bulanan** (angka rupiah)
- **Memiliki NPWP?** (Yes/No radio)

**Upload Dokumen:**
- **Foto KTP** (upload image)
  - Wajib diisi
  - Auto-detect duplicate (hash)
  - Kalau KTP sudah pernah diajukan → error
  
- **Produk yang Diajukan** (dropdown)
  - List produk dari database
  - Optional (bisa kosong)

**Status & Follow-up:**
- **Status Pengajuan** (auto: "Pending")
  - Admin/SATOR yang update jadi Approved/Rejected
  
- **Kendala** (dropdown, kalau rejected)
  - Data tidak lengkap
  - Tidak lolos BI checking
  - Penghasilan tidak cukup
  - Lainnya

- **Kendala Lainnya** (text, kalau pilih "Lainnya")

- **Bukti Hasil** (upload, optional)
  - Screenshot approval
  - Dokumen hasil

#### **Dashboard VAST Finance:**

**Summary Cards:**
```
┌─────────────┬─────────────┬─────────────┬─────────────┐
│   Total     │  Approved   │  Rejected   │   Pending   │
│     15      │      8      │      3      │      4      │
└─────────────┴─────────────┴─────────────┴─────────────┘

Approval Rate: 53% (8/15)
```

**List Pengajuan:**
```
Table (sortable):
┌──────────────┬────────────┬──────────┬─────────┬────────────┐
│ Nama        │ Produk     │ Status   │ Tanggal │ Action     │
├──────────────┼────────────┼──────────┼─────────┼────────────┤
│ Budi        │ Y19s       │ Approved │ 1/1/26  │ [Detail]   │
│ Ani         │ V40        │ Pending  │ 2/1/26  │ [Update]   │
│ Cici        │ Y400       │ Rejected │ 30/12   │ [Detail]   │
└──────────────┴────────────┴──────────┴─────────┴────────────┘
```

**Filter:**
- Periode (Hari ini, Minggu ini, Bulan ini, Custom)
- Status (Semua, Pending, Approved, Rejected)

**Actions:**
- **[Detail]** → lihat full info pengajuan
- **[Update Status]** → ubah Pending → Approved/Rejected (kalau ada konfirmasi)

---

### **8. LAPORAN ALLBRAND (Competitor Analysis)**
**File:** `laporan_allbrand_form`  
**URL:** `/promotor/laporan/allbrand/`

#### **Tujuan:** Laporkan stok competitor brands di toko

**Yang harus diisi:**

**Untuk setiap brand:**
- VIVO
- Samsung
- OPPO
- Realme
- Xiaomi
- Infinix

**Data per brand:**

**A. Stock Count by Price Range:**
```
Brand: Samsung
- Under 2 juta: [5] unit
- 2-4 juta: [8] unit
- 4-6 juta: [3] unit
- 6 juta+: [2] unit

Total: 18 unit
```

**B. Promotor Count:**
```
Jumlah promotor Samsung di toko: [2] orang
```

**Leasing Availability (Checkbox):**
```
Leasing yang tersedia di toko:
☑ HCI
☑ Kredivo
☐ Indodana
☑ FIF
```

**Promotor VIVO Manual Input:**
```
Jumlah promotor VIVO (manual): [1] orang
(Auto-count dari sistem: 1 orang)
```

#### **Auto-calculation:**

System otomatis hitung VIVO sales dari database:
```
VIVO Today Sales (Auto):
- Under 2 juta: 3 unit
- 2-4 juta: 5 unit
- 4-6 juta: 2 unit
- 6 juta+: 1 unit
```

#### **Yang terjadi:**

1. **Validasi:**
   - Minimal 1 brand harus diisi
   - Angka tidak boleh negatif

2. **Simpan:**
   - Tabel `laporan_allbrand`
   - Include auto-calculated VIVO data
   
3. **Notifikasi Discord:**
   - Ke channel allbrand tim
   - Summary comparison:
     ```
     📊 Allbrand Report - Transmart MTC
     
     VIVO: 11 unit (5 promotor)
     Samsung: 18 unit (2 promotor)
     OPPO: 12 unit (1 promotor)
     ...
     
     Leasing: HCI, Kredivo, FIF
     ```

---

### **9. LAPORAN FOLLOWER TIKTOK**
**File:** `laporan_follower_form`  
**URL:** `/promotor/laporan/follower/`

#### **Yang harus diisi:**

**Data Follower:**
- **Username TikTok** (text)
  - Tanpa @ (system auto-add)
  - Contoh input: "budisantoso" → saved as "@budisantoso"
  - Validasi: unique (tidak boleh duplikat)
  
- **Bukti Screenshot** (upload multiple images)
  - Screenshot profile follower
  - Screenshot follow notification
  - Min 1 foto, max 5 foto
  
- **Catatan** (text area, optional)
  - Source: dari mana follower ini
  - Engagement: apakah active follower
  - Keterangan lain

#### **Yang terjadi:**

1. **Validasi:**
   - Username harus unique (belum pernah dilaporkan)
   - Minimal 1 foto wajib ada
   
2. **Upload:**
   - Semua screenshot ke Cloudinary (folder: follower_foto)
   - Simpan sebagai JSON array URLs
   
3. **Simpan:**
   - Tabel `follower_tik_tok`
   - Link ke promotor & toko
   
4. **Notifikasi Discord:**
   - Ke channel aktivitas
   - "Follower baru: @budisantoso"
   - Attach screenshot pertama

---

### **10. CEK STOK GUDANG**
**File:** `cek_stok_view`  
**URL:** `/promotor/cek-stok/`

#### **Fitur:** View-only, cek stok available

**Yang ditampilkan:**

```
Filter: [Semua Series ▼]  Search: [_______________] 🔍

┌────────────────────────────────────────────────────┐
│ Y-Series                                           │
├────────────────────────────────────────────────────┤
│ Y19s 8/128GB Black                                 │
│ SRP: Rp 2,500,000                                  │
│ Gudang: 15 unit | OTW: 5 unit                      │
│ Status: ✅ Cukup                                   │
├────────────────────────────────────────────────────┤
│ Y400 6/128GB Gold                                  │
│ SRP: Rp 2,200,000                                  │
│ Gudang: 3 unit | OTW: 0 unit                       │
│ Status: ⚠️ Tipis                                   │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│ V-Series                                           │
├────────────────────────────────────────────────────┤
│ V40 12/256GB Black                                 │
│ SRP: Rp 4,500,000                                  │
│ Gudang: 0 unit | OTW: 10 unit                      │
│ Status: 🚚 Transit                                 │
└────────────────────────────────────────────────────┘
```

**Status Legend:**
- ✅ Cukup = Gudang > 10 unit
- ⚠️ Tipis = Gudang 1-10 unit
- ❌ Kosong = Gudang 0 unit, OTW 0 unit
- 🚚 Transit = Gudang 0 unit, OTW > 0 unit

**Fitur:**
- Filter by series (Y, V, X, dll)
- Search by nama model
- Real-time data from database
- No action buttons (read-only)

---

### **11. AKTIVITAS PROMOTOR**
**File:** `aktivitas_promotor_view`, `aktivitas_detail_api`  
**URL:** `/promotor/dashboard/aktivitas/`

#### **Summary View:**

**Calendar Grid:**
```
       Januari 2026
   Mo Tu We Th Fr Sa Su
              1  2  3  4  5
    6  7  8  9 10 11 12
   13 14 15 16 17 18 19
   20 21 22 23 24 25 26
   27 28 29 30 31

Legend:
🟢 = Ada aktivitas
⚪ = Tidak ada aktivitas
🔴 = Target tidak tercapai
```

**Daily Activity Card (Onclick tanggal):**
```
📅 2 Januari 2026

✅ Absensi: 08:00 WITA
💰 Penjualan: 5 unit (Rp 12.5 juta)
📦 Input Stok: 3 unit
📣 Promosi: 2 platform
💳 VAST: 1 pengajuan

Target Achievement: 75% 🎯
```

**Monthly Summary:**
```
📊 Bulan Ini (Januari)

Total Hari Kerja: 20 hari
Hadir: 18 hari (90%)
Tidak Hadir: 2 hari

Total Penjualan: 87 unit
Target: 100 unit (87% achievement)

Total Bonus: Rp 13,500,000
```

---

## 🔄 WORKFLOW HARIAN PROMOTOR (Typical Day)

### **Pagi (08:00)**
1. **Buka app**
2. **Clock In:**
   - Ambil foto selfie
   - GPS auto-detect
   - Submit absensi
3. **Cek Dashboard:**
   - Lihat target hari ini
   - Lihat stok available
4. **Cek Stok Gudang:**
   - View stok ready
   - Note produk yang mau di-restock

### **Siang (11:00-14:00) - PEAK TIME**
1. **Ada customer berminat:**
   - Show produk
   - Explain features
   - Close deal!
   
2. **Input Penjualan:**
   - Scan IMEI barcode
   - System auto-detect produk
   - Isi harga jual, tipe pembayaran
   - Foto customer (optional)
   - Submit → dapat bonus instant!
   
3. **Customer kredit:**
   - Buka form VAST Finance
   - Isi data customer
   - Foto KTP
   - Submit pengajuan
   - Tunggu approval dari admin

### **Sore (15:00-17:00)**
1. **Stok datang:**
   - Input stok baru
   - Scan IMEI produk masuk
   - Pilih tipe: Display/Ready/Transit
   
2. **Update stok habis:**
   - Laporan produk kosong
   - Request restock

### **Malam (18:00-20:00)**
1. **Posting promosi:**
   - Upload video TikTok
   - Post Instagram story
   - Facebook post
   
2. **Laporan promosi:**
   - Screenshot postingan
   - Input ke app (per platform)
   - Submit

3. **Follower baru:**
   - Ada yang follow TikTok
   - Laporan follower baru
   - Screenshot + submit

4. **Laporan Allbrand:**
   - Hitung stok competitor
   - Count promotor brand lain
   - Submit report

### **Malam (Before Sleep)**
1. **Cek Achievement:**
   - Lihat bonus hari ini
   - Lihat progress target
   - Plan besok

---

## 📊 YANG PROMOTOR HARUS TAHU

### **Target Bulanan (Contoh):**
```
Target Ahmad - Januari 2026:
- Omzet: Rp 50,000,000
- Unit Fokus: 20 unit
- Unit Y400: 5 unit
- Unit Y29: 8 unit
- Unit V-series: 7 unit
- TikTok followers: 50 orang
- Promosi post: 30 post
- VAST Finance: 10 aplikasi
```

### **Perhitungan Bonus:**

**Regular Product:**
```
Y19s (Fokus) → Rp 150,000 per unit
Jual 5 unit = 5 × 150k = Rp 750,000
```

**Special Product (2=1):**
```
Y03t (Murah) → Rp 100,000 per 2 unit
Jual 4 unit = (4÷2) × 100k = Rp 200,000
```

**Team Bonus (dari SATOR):**
```
Kalau team achievement > 90%:
+Rp 500,000 bonus tim
```

---

## ⚠️ MASALAH DI SISTEM LAMA

### **1. Access via Discord**
❌ Harus pakai slash command (`/jualan`, `/stok`)  
❌ Membingungkan, banyak command  
❌ Gampang salah ketik  
❌ Tidak user-friendly di mobile  

### **2. UI Kurang Optimal**
❌ Web-based, kurang smooth di HP  
❌ Camera handling ribet  
❌ GPS tidak akurat  
❌ Loading lambat  

### **3. Workflow Tidak Jelas**
❌ Terlalu banyak halaman  
❌ Navigation membingungkan  
❌ Tidak ada tutorial/onboarding  

### **4. Offline Tidak Bisa**
❌ Kalau internet mati, tidak bisa input  
❌ Data hilang kalau reload page  
❌ Risky untuk promotor di area signal lemah  

---

## ✅ YANG HARUS ADA DI APP BARU

### **Must Have:**
1. ✅ **Native Mobile App** (Flutter)
2. ✅ **Offline-capable** (queue for sync)
3. ✅ **Simple navigation** (bottom nav)
4. ✅ **Quick actions** (1-tap dari home)
5. ✅ **Barcode scanner** (built-in)
6. ✅ **Camera** (native, smooth)
7. ✅ **GPS** (accurate location)
8. ✅ **Push notifications** (reminders)
9. ✅ **Dashboard yang jelas** (at-a-glance)
10. ✅ **Achievement tracking** (real-time)

### **Nice to Have:**
- 🎯 Gamification (badges, leaderboard)
- 📊 AI insights ("Fokus produk X hari ini!")
- 💬 In-app chat (dengan SATOR)
- 📸 Photo gallery (history foto penjualan)
- 📅 Calendar view (activities per day)

---

## 📱 PRIORITAS FITUR UNTUK REBUILD

### **Priority 1: CORE (Week 1-3)**
1. Dashboard/Home
2. Input Penjualan
3. Input Stok
4. Absensi (Clock In)
5. Lihat Bonus & Achievement

### **Priority 2: EXTENDED (Week 4-6)**
6. Pengajuan VAST Finance
7. Laporan Promosi Medsos
8. Cek Stok Gudang
9. Dashboard Aktivitas

### **Priority 3: OPTIONAL (Week 7-8)**
10. Laporan Allbrand
11. Laporan Follower TikTok
12. Export data

---

**NEXT:** Mau saya detail-kan workflow per halaman seperti apa? Atau mau saya buatkan wireframe/mockup dulu?
