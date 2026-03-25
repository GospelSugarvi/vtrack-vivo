# 💳 VAST FINANCE SYSTEM - ANALYSIS

**Tanggal:** 2 Januari 2026
**Status:** COMPLETE ANALYSIS
**Type:** Shadow Tracking System (Manual Entry)

---

## 🎯 OVERVIEW

**VAST Finance** adalah partner leasing/kredit yang digunakan VIVO.
Aplikasi kita berfungsi untuk **mencatat dan memonitor** performa pengajuan kredit tim promotor.

**PENTING:**
Aplikasi ini **TIDAK** terhubung secara sistem (API) dengan VAST Finance.
- Promotor melakukan pengajuan di **Aplikasi Official VAST**.
- Promotor **mencatat hasilnya** di aplikasi ini (sebagai bukti kerja & achievement).

---

## 🔄 WORKFLOW DETAIL

### **1. PROMOTOR: Input Pengajuan**
Promotor mengisi form setelah selesai proses di aplikasi VAST.

**Data yang Diinput:**
- **Data Pemohon:** Nama, Telepon, Pekerjaan, Penghasilan, NPWP.
- **Dokumen:**
  - `foto_ktp`: Foto KTP customer (wajib).
  - `bukti_hasil`: Screenshot layar HP dari aplikasi VAST yang menunjukkan status (Approved/Rejected/Pending).
- **Hasil Pengajuan (Manual Select):**
  - ✅ **Approved:** Jika disetujui limit. Input `Total Limit` yang didapat.
  - ❌ **Rejected:** Jika ditolak. Input `Kendala` (e.g., KTP Rusak, BI Checking, dll).
  - ⏳ **Pending:** Jika butuh survei lanjutan/analis.

**Validasi Sistem:**
- **KTP Hash Check:** Sistem cek apakah foto KTP yang sama sudah pernah diinput. Mencegah duplikasi data / spam submission promotor.

### **2. PROMOTOR: Konversi (Deal)**
Jika status awal **Approved**, itu bulum tentu jadi penjualan (cair).
Customer bisa saja batal ambil barang.

**Flow Konversi:**
- Dashboard Promotor ada tab "Pending Ambil Barang".
- Jika customer jadi transaksi: Klik **"Ambil Barang"**.
- Input: `Produk yang diambil`.
- Status berubah: `Approved` + `Sudah Ambil`.
- **INI YANG DIHITUNG SEBAGAI DEAL/PENJUALAN KREDIT.**

### **3. SATOR/SPV: Monitoring**
Leader memantau performa kredit tim.

**Metrics:**
- **Total Pengajuan:** Jumlah submitting (produktivitas nawarin kredit).
- **Approval Rate:** % Disetujui (kualitas customer).
- **Conversion Rate:** % Approved yang jadi ambil barang.
- **Achievement:** Total Pengajuan vs Target Kredit Bulanan.

---

## 📊 DATABASE SCHEMA (`PengajuanKredit`)

```sql
CREATE TABLE pengajuan_kredit (
  id BIGSERIAL PRIMARY KEY,
  pengguna_id BIGINT REFERENCES users(id), -- Promotor
  toko_id BIGINT REFERENCES toko(id),
  
  -- Data Customer
  nama_pemohon VARCHAR(100),
  telepon_pemohon VARCHAR(20),
  pekerjaan_pemohon VARCHAR(100),
  penghasilan_bulanan BIGINT,
  memiliki_npwp BOOLEAN,
  
  -- Bukti & Validasi
  foto_ktp_path TEXT,    -- Cloudinary URL
  foto_ktp_hash VARCHAR(64), -- SHA256 hash untuk dedup
  bukti_hasil_path TEXT, -- Cloudinary URL (screenshot app VAST)
  
  -- Hasil Pengajuan
  status_pengajuan VARCHAR(20), -- 'Approved', 'Rejected', 'Pending'
  
  -- Detail Jika Approved
  total_limit BIGINT NULL,
  
  -- Detail Jika Rejected
  kendala VARCHAR(100) NULL, -- 'BI Checking', 'KTP Rusak', dll
  kendala_lainnya TEXT NULL,
  
  -- Tracking Konversi
  status_ambil_barang VARCHAR(20) DEFAULT 'Belum Ambil', -- 'Belum Ambil', 'Sudah Ambil'
  tanggal_ambil_barang TIMESTAMP NULL,
  produk_diajukan_id BIGINT REFERENCES produk(id) NULL,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP
);
```

---

## 📱 UI/UX REQUIREMENTS (REBUILD)

### **1. OCR untuk KTP (Recommended Update)**
- Saat ini: Upload foto → Hash.
- **Upgrade:** Gunakan Gemini/Tesseract untuk **auto-fill** Nama & NIK dari foto KTP. Mempercepat input promotor.

### **2. Quick Update Action**
- Di Dashboard Promotor, list "Approved (Belum Ambil)" harus sangat mudah diakses.
- Tombol besar **"CUSTOMER AMBIL BARANG SEKARANG"**.

### **3. Target Visualization**
- Tampilkan gauge/progress bar khusus kredit di Home Promotor.
- "Target: 10 Pengajuan | Capaian: 4 | Kurang: 6".

### **4. Leader Insight**
- Highlight promotor dengan **High Rejection Rate** (mungkin salah target market).
- Highlight promotor dengan **High Approval but Low Conversion** (kurang closing skill).

---

## ⚠️ PAIN POINTS & SOLUSI

| Pain Point | Solusi Rebuild (Flutter) |
| :--- | :--- |
| Promotor malas input 2x (App VAST + App Ini) | Buat form se-simple mungkin. Auto-fill data via OCR KTP. |
| Lupa update status "Sudah Ambil" | Notifikasi reminder untuk pengajuan Approved yg sudah > 24 jam tapi belum ambil. |
| Duplikasi data | Pertahankan KTP Hash logic. |
| Susah monitor performa harian | Widget khusus "Today's Credit Stats" di dashboard SATOR. |

---

**Analisis selesai.** Fitur ini cukup straightforward tapi critical untuk extra incentive promotor.
