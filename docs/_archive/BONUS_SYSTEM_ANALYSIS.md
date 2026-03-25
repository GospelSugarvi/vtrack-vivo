# 💰 BONUS SYSTEM - FINAL LOCKED SPECIFICATION
**Date:** 5 Januari 2026  
**Status:** 100% FINALIZED ✅  
**Source:** Upah dan Benefit PC NTT Desember 2025 + KPI SATOR Desember 2025

---

## 🎯 SYSTEM PURPOSE & PHILOSOPHY

### **Core Purpose:**
```
✅ MONITORING & TRACKING tool untuk SPV/SATOR/Manager
✅ ESTIMASI & PROYEKSI bonus (bukan official calculation)
✅ ALERT & REMINDER system untuk status promotor
✅ Dashboard visibility untuk team performance

BUKAN:
❌ Sistem payroll official (HRD punya sistem sendiri)
❌ Source of truth untuk payment
❌ Auto-process untuk status changes
❌ Replacement sistem management

FILOSOFI:
"Close Enough is Good Enough"
- Proyeksi mendekati actual (95-98% accuracy target)
- Membantu decision making & early warning
- Mengurangi manual tracking Excel
- Admin manual control untuk final status
```

---

## 🎯 OVERVIEW: BONUS SYSTEM COMPLEXITY

Sistem bonus VIVO NTT adalah sistem **MULTI-LAYER** yang sangat kompleks:

1. **3 Tipe User** dengan aturan berbeda: Promotor Official, Promotor Training, SATOR
2. **Range-Based Bonus** (bukan per produk fixed)
3. **Special Case Products** (X Series, Y02/Y03T/Y04S dengan aturan khusus)
4. **Bonus Masa Kerja** (seniority bonus)
5. **KPI-Based Calculation** untuk SATOR
6. **Reward Khusus** untuk produk tertentu (Y400, Y29, V60 Lite)

---

## 📋 PART 1: BONUS PROMOTOR

### **A. PROMOTOR OFFICIAL**

#### **Kriteria Official:**
```
✅ Penjualan 3 bulan berturut-turut minimal Rp 120 juta/bulan
✅ Sudah ikut & lulus ujian
```

#### **Kompensasi Tetap:**
```
Gaji Pokok: Rp 2.185.000/bulan

Tunjangan (Variable):
├─ Middle: Rp 315.000 (achieve Rp 180jt - Rp 249jt)
└─ High: Rp 815.000 (achieve min. Rp 250jt)

Target Standar: Rp 120.000.000/bulan
```

---

### **B. PROMOTOR TRAINING**

#### **Status:**
```
Promotor baru masuk (belum official)
```

#### **Kompensasi Tetap:**
```
Gaji Pokok: Rp 1.000.000/bulan
Tunjangan: Rp 500.000/bulan

Target Standar: Rp 60.000.000 - Rp 80.000.000/bulan
```

---

### **C. INSENTIF DASAR (Per Unit Sold)**

#### **RANGE-BASED BONUS:**

| Range Harga (SRP) | Official | Training | Notes |
|-------------------|----------|----------|-------|
| < Rp 2.000.000 | **Rp 10.000**/unit | **Rp 7.000**/unit | Produk entry-level |
| Rp 2.000.000 - Rp 2.999.999 | **Rp 25.000**/unit | **Rp 20.000**/unit | Mid-range |
| Rp 3.000.000 - Rp 3.999.999 | **Rp 45.000**/unit | **Rp 40.000**/unit | Upper mid |
| Rp 4.000.000 - Rp 4.999.999 | **Rp 60.000**/unit | **Rp 50.000**/unit | Premium |
| Rp 5.000.000 - Rp 5.999.999 | **Rp 80.000**/unit | **Rp 60.000**/unit | High-end |
| > Rp 6.000.000 | **Rp 110.000**/unit | **Rp 90.000**/unit | Flagship |

**Key Insight:**
- Bonus **BUKAN fixed per produk**, tapi **berdasarkan RANGE HARGA**
- **Harga produk** (SRP) menentukan bonus
- Official dapat **lebih tinggi** dari Training (gap Rp 3k - Rp 20k)

---

### **D. TIPE KHUSUS (SPECIAL CASES)**

#### **1. X Series (Bonus Cash - BUKAN Insentif Dasar)**

```
X300: Rp 250.000/unit (FLAT BONUS)
X300 Pro: Rp 300.000/unit (FLAT BONUS)
X Fold 5 Pro: Rp 350.000/unit (FLAT BONUS)

PENTING:
❌ TIDAK ADA insentif dasar (range-based)
✅ HANYA bonus cash fixed
✅ Sama untuk Official & Training
```

#### **2. Y02, Y03T, Y04S (Low-End dengan Rasio 2:1)**

```
Official: Rp 5.000/unit
Training: Rp 4.000/unit

RASIO KHUSUS:
⚠️ 2 unit dihitung 1 unit

Artinya:
- Jual 2 unit Y02 → Bonus Official: Rp 5.000 (bukan Rp 10.000)
- Jual 2 unit Y03T → Bonus Training: Rp 4.000 (bukan Rp 8.000)
- Jual 6 unit Y04S → Dihitung 3 unit → Rp 15.000 (Official)

Ini yang dimaksud "rasio hitung 2=1"!
```

---

### **E. BONUS MASA KERJA (Seniority Bonus)**

| Masa Kerja | Bonus/Bulan | Notes |
|------------|-------------|-------|
| 1 Tahun | Rp 50.000 | |
| 2 Tahun | Rp 100.000 | |
| 3 Tahun | Rp 150.000 | |
| 4 Tahun | Rp 200.000 | |
| 5 Tahun | Rp 250.000 | **Training juga dapat Rp 50.000** |
| 6 Tahun | Rp 300.000 | |
| 7 Tahun | Rp 350.000 | |
| 8 Tahun | Rp 400.000 | |

**Key Points:**
- Bonus masa kerja **terpisah** dari insentif penjualan
- Dibayar **per bulan** (bukan one-time)
- Training yang 5 tahun dapat **Rp 50.000** (special case)

---

## 📊 PART 2: BONUS SATOR

### **A. SISTEM KPI SATOR (4 KATEGORI PENILAIAN)**

```
┌──────────────────────────┬────────┬────────────────────┐
│ Kategori                 │ Bobot  │ Max Achievement    │
├──────────────────────────┼────────┼────────────────────┤
│ Sell Out All Type        │ 40%    │ 100% = 40%         │
│ Sell Out Produk Fokus    │ 30%    │ 100% = 30%         │
│ Sell In All Type         │ 20%    │ 100% = 20%         │
│ KPI MA (Manager Area)    │ 10%    │ Kebijakan Manager  │
└──────────────────────────┴────────┴────────────────────┘

SYARAT CAIR INSENTIF:
Total Persentase Pencapaian minimal 80%
```

#### **Contoh Perhitungan Bobot:**

```
SATOR Antonio - Januari 2026:

Sell Out All Type: 80% achieve
└─ Bobot: 80% × 40% = 32%

Sell Out Produk Fokus: 100% achieve
└─ Bobot: 100% × 30% = 30%

Sell In All Type: 90% achieve
└─ Bobot: 90% × 20% = 18%

KPI MA: 10% (Manager kasih full)
└─ Bobot: 10%

TOTAL AKHIR: 32 + 30 + 18 + 10 = 90%

✅ 90% ≥ 80% → INSENTIF CAIR!
❌ Jika < 80% → INSENTIF TIDAK CAIR!
```

---

### **B. POIN INSENTIF SATOR (Sell Out All Type)**

**Sistem:** 1 Poin = Rp 1.000

| Range Harga (SRP) | Poin/Unit |
|-------------------|-----------|
| Rp 1.000.000 - Rp 1.399.999 | **0.7 poin** |
| Rp 1.400.000 - Rp 1.899.999 | **1.5 poin** |
| Rp 1.999.000 - Rp 2.499.999 | **2.0 poin** |
| Rp 2.500.000 - Rp 2.999.999 | **2.5 poin** |
| Rp 3.000.000 - Rp 3.499.999 | **4.5 poin** |
| Rp 3.500.000 - Rp 3.999.999 | **8.0 poin** |
| Rp 4.000.000 - Rp 4.499.999 | **10.0 poin** |
| Rp 4.500.000 - Rp 5.999.999 | **14.0 poin** |
| > Rp 6.000.000 | **18.0 poin** |

**Contoh:**
```
SATOR Antonio - Sell Out Januari:
├─ 10 unit Y400 (Rp 3.5jt) → 10 × 8.0 = 80 poin
├─ 15 unit Y29 (Rp 2.8jt) → 15 × 2.5 = 37.5 poin
└─ 5 unit V60 (Rp 4.2jt) → 5 × 10.0 = 50 poin

Total Poin: 80 + 37.5 + 50 = 167.5 poin
Insentif Sell Out: 167.5 × Rp 1.000 = Rp 167.500

TAPI! Ini baru 40% dari total (kalau achieve 100%)
Kalau achieve Sell Out All Type hanya 80%:
└─ Rp 167.500 × 80% = Rp 134.000 (yang masuk ke bobot)
```

---

### **C. REWARD KHUSUS SATOR (KPI Desember 2025)**

#### **Syarat:** Indikator Sell Out = **100%** untuk kategori tersebut

#### **1. Y400 Series:**

| Skala Unit | Reward |
|------------|--------|
| < 30 unit | Rp 500.000 |
| 30 - 50 unit | Rp 750.000 |
| > 50 unit | **Rp 1.250.000** |

#### **2. Y21Ds / Y29s:**

| Skala Unit | Reward |
|------------|--------|
| < 50 unit | Rp 500.000 |
| 50 - 80 unit | **Rp 1.250.000** |
| > 80 unit | **Rp 1.500.000** |

#### **3. V60 Lite Series:**

| Skala Unit | Reward |
|------------|--------|
| < 20 unit | Rp 600.000 |
| 20 - 50 unit | Rp 800.000 |
| > 50 unit | **Rp 1.500.000** |

**PENTING:**
```
✅ Reward cair HANYA jika Sell Out kategori tersebut = 100%
✅ Reward adalah TAMBAHAN insentif (di luar poin)
❌ Jika < 100%, tidak dapat reward (bahkan kalau 99%)

Contoh:
SATOR Antonio:
- Sell Out Y400: 95% (45 unit)
  └─ ❌ Tidak dapat reward (harus 100%)
  
- Sell Out Y29: 100% (55 unit)
  └─ ✅ Dapat reward Rp 1.250.000 (skala 50-80 unit)
```

---

### **D. SANKSI/DENDA SATOR**

```
⚠️ Jika pencapaian kategori < 80%

Denda: Rp 100.000 per kategori

Contoh:
SATOR Antonio - Januari:
├─ Sell Out All Type: 75% ❌ (< 80%)
│  └─ Denda: Rp 100.000
├─ Sell Out Fokus: 85% ✅ (OK)
├─ Sell In All Type: 70% ❌ (< 80%)
│  └─ Denda: Rp 100.000
└─ KPI MA: 10% ❌ (< 80%)
   └─ Denda: Rp 100.000

Total Denda: Rp 300.000
Total Achievement: 75+85+70+10 = 240/4 = 60%

❌ Total < 80% → INSENTIF TIDAK CAIR
❌ Bayar denda: Rp 300.000
```

---

## 🔥 KEY INSIGHTS & DESIGN IMPLICATIONS

### **1. RANGE-BASED vs PRODUCT-BASED**

```
❌ OLD MINDSET: Bonus per produk (Y400 = Rp 50k)
✅ NEW REALITY: Bonus per range harga (Rp 3-4jt = Rp 45k)

Implikasi:
- Database HARUS punya kolom "harga_srp" per produk
- Bonus calculation pakai WHERE harga BETWEEN x AND y
- Kalau harga produk berubah → bonus otomatis berubah
- Admin atur "bonus rules" per range, bukan per produk
```

### **2. SPECIAL CASES HANDLING**

```
3 Jenis Exception:
1. X Series → Flat bonus (ignore range)
2. Y02/Y03T/Y04S → Rasio 2:1 (qty dibagi 2)
3. Produk SATOR Reward → Achievement 100% required

Database Design Need:
- Column: bonus_type (range | flat | ratio)
- Column: bonus_ratio (default 1, untuk Y02 = 0.5)
- Column: special_reward_eligible (boolean)
```

### **3. MULTI-CALCULATION LAYERS**

```
Promotor Bonus:
└─ Layer 1: Insentif Dasar (range/flat/ratio)
   Layer 2: Bonus Masa Kerja (seniority)
   Layer 3: Tunjangan (achievement-based)

SATOR Bonus:
└─ Layer 1: Poin Insentif (sell out)
   Layer 2: KPI Bobot (4 kategori)
   Layer 3: Reward Khusus (100% achievement)
   Layer 4: Denda (< 80%)
```

### **4. FLEXIBILITY REQUIREMENTS**

```
Admin HARUS Bisa Ubah:
✅ Range harga (min-max)
✅ Bonus per range (official & training)
✅ Special case products (X Series bonus, Y02 ratio)
✅ Masa kerja bonus amount
✅ SATOR poin per range
✅ SATOR reward skala & amount
✅ SATOR bobot kategori (40-30-20-10)
✅ Threshold (80% cair, 100% reward)
✅ Denda amount
✅ Periode berlaku (bulan/tahun)
✅ Area berlaku (Kupang, Sumba, dll)

TANPA CODING!
```

---

## 🎯 CRITICAL QUESTIONS FOR FINALIZATION

### **1. SPV Bonus?**
User bilang "SPV, SATOR, Promotor ada bonus", tapi dokumen hanya ada SATOR & Promotor.

❓ **Apakah SPV bonus sama dengan SATOR?**
❓ **Atau SPV punya aturan sendiri?**

---

### **2. Periode Berlaku?**
Dokumen adalah "Desember 2025".

❓ **Apakah aturan ini berlaku sampai kapan?**
❓ **Januari 2026 sama atau beda?**
❓ **Berapa sering aturan berubah?** (setiap bulan? quarter?)

---

### **3. Area Berlaku?**
Dokumen untuk "NTT" (Nusa Tenggara Timur).

❓ **Apakah setiap area punya aturan bonus sendiri?**
❓ **Atau semua area pakai aturan yang sama?**
❓ **Jika berbeda, apa yang beda?** (hanya amount? atau struktur juga?)

---

### **4. Reward Khusus SATOR - Dinamis?**
Reward untuk Y400, Y29, V60 Lite adalah "KPI Khusus **Desember 2025**".

❓ **Apakah setiap bulan ada produk reward khusus berbeda?**
❓ **Atau tetap produk yang sama, tapi amount/skala berubah?**
❓ **Siapa yang tentukan?** (HRD? Manager Area? Admin?)

---

### **5. Bonus Training yang 5 Tahun?**
Ada catatan khusus "Training juga dapat 50k" untuk masa kerja 5 tahun.

❓ **Maksudnya:** Training yang sudah 5 tahun **tetap Training** (tidak jadi Official)?
❓ **Atau:** Training yang 5 tahun **otomatis jadi Official**?

---

### **6. Conversion Rules?**
Promotor Training jadi Official kalau "3 bulan berturut minimal 120jt + lulus ujian".

❓ **Apakah sistem perlu auto-detect & suggest conversion?**
❓ **Atau fully manual oleh admin/HRD?**

---

## 📋 NEXT STEPS

1. **User jawab 6 pertanyaan critical di atas**
2. **Finalize bonus rules structure**
3. **Design database schema untuk bonus system**
4. **Design admin UI untuk bonus management**
5. **Lanjut ke Product Management** (yang juga terkait bonus)

---

**Status:** Analisis Complete, Waiting for Clarification ✅
