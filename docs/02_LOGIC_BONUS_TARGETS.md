# 💰 BONUS SYSTEM - FINAL LOCKED SPECIFICATION
**Date:** 5 Januari 2026  
**Status:** 100% FINALIZED & LOCKED ✅  
**Last Updated:** 5 Januari 2026, 17:16 WITA

---

## 🎯 SYSTEM PURPOSE

### **What This System IS:**
```
✅ MONITORING & TRACKING tool untuk SPV/SATOR/Manager
✅ PROYEKSI & ESTIMASI bonus real-time
✅ ALERT & WARNING system (kandidat official, warning downgrade)
✅ Dashboard visibility (performance tracking)
✅ Manual admin control (status changes)
```

### **What This System IS NOT:**
```
❌ Official payroll system (HRD punya sistem sendiri)
❌ Source of truth untuk final payment
❌ Auto-processing status changes
❌ Replacement sistem management pusat

FILOSOFI: "Close Enough is Good Enough"
Target: 95-98% accuracy untuk proyeksi
```

---

## 📋 PART 1: BONUS PROMOTOR

### **A. DUA TIPE PROMOTOR**

#### **1. PROMOTOR TRAINING (Baru Masuk)**

**Kriteria:**
- Promotor baru masuk
- Belum lulus ujian official
- Belum 3 bulan berturut ≥ Rp 120 juta

**Kompensasi Tetap:**
```
Gaji Pokok: Rp 1.000.000/bulan
Tunjangan: Rp 500.000/bulan
Target Standar: Rp 60.000.000 - Rp 80.000.000/bulan

SYARAT MINIMUM BONUS:
⚠️ PENCAPAIAN HARUS ≥ Rp 60.000.000/bulan
❌ Jika < Rp 60 juta → Insentif tidak dibayar (Rp 0)
```

---

#### **2. PROMOTOR OFFICIAL**

**Kriteria:**
- Penjualan 3 bulan berturut ≥ Rp 120 juta
- Sudah lulus ujian official

**Kompensasi Tetap:**
```
Gaji Pokok: Rp 2.185.000/bulan

Tunjangan (Variable):
├─ Middle: Rp 315.000 (achieve Rp 180jt - Rp 249jt)
└─ High: Rp 815.000 (achieve min. Rp 250jt)

Target Standar: Rp 120.000.000/bulan

SYARAT MINIMUM BONUS:
⚠️ PENCAPAIAN HARUS ≥ Rp 120.000.000/bulan
❌ Jika < Rp 120 juta → Insentif tidak dibayar (Rp 0)
```

---

### **B. INSENTIF PENJUALAN (3 JENIS)**

#### **JENIS 1: RANGE-BASED BONUS (Default)**

Bonus berdasarkan **HARGA PRODUK** (SRP), bukan nama produk.

| Range Harga (SRP) | Official | Training | Notes |
|-------------------|----------|----------|-------|
| < Rp 2.000.000 | Rp 10.000/unit | Rp 7.000/unit | Entry-level |
| Rp 2.000.000 - Rp 2.999.999 | Rp 25.000/unit | Rp 20.000/unit | Mid-range |
| Rp 3.000.000 - Rp 3.999.999 | Rp 45.000/unit | Rp 40.000/unit | Upper mid |
| Rp 4.000.000 - Rp 4.999.999 | Rp 60.000/unit | Rp 50.000/unit | Premium |
| Rp 5.000.000 - Rp 5.999.999 | Rp 80.000/unit | Rp 60.000/unit | High-end |
| > Rp 6.000.000 | Rp 110.000/unit | Rp 90.000/unit | Flagship |

**Contoh:**
```
Promotor Official jual:
- Y29 (Rp 2.8 juta): 5 unit × Rp 25.000 = Rp 125.000
- Y400 (Rp 3.5 juta): 3 unit × Rp 45.000 = Rp 135.000
- V60 (Rp 4.2 juta): 2 unit × Rp 60.000 = Rp 120.000

Total Insentif Range-Based: Rp 380.000
```

---

#### **JENIS 2: FLAT BONUS CASH (X Series)**

Produk X Series **TIDAK pakai range-based**, tapi **flat bonus cash**.

| Produk | Bonus (Official & Training) |
|--------|-------------|
| X300 | Rp 250.000/unit |
| X300 Pro | Rp 300.000/unit |
| X Fold 5 Pro | Rp 350.000/unit |

**Catatan:**
```
✅ X Series masuk ke PENCAPAIAN target bulanan
✅ X Series masuk ke TIPE FOKUS (tapi tidak punya target detail)
❌ X Series TIDAK dapat insentif range-based
✅ X Series HANYA dapat bonus cash flat
```

**Contoh:**
```
Promotor Training jual:
- X300 (Rp 8 juta): 1 unit → Bonus: Rp 250.000 (bukan Rp 90k dari range >6jt)
- X300 Pro (Rp 9 juta): 1 unit → Bonus: Rp 300.000

Total Bonus Cash: Rp 550.000
```

---

#### **JENIS 3: BONUS RASIO 2:1 (Produk Low-End)**

Produk tertentu pakai **rasio 2 unit dihitung 1 unit**.

**Produk:**
- Y02
- Y03T
- Y04S

**Bonus:**
- Official: Rp 5.000/unit (setelah rasio)
- Training: Rp 4.000/unit (setelah rasio)

**Alasan:** Margin terendah, produk terlaris.

**Formula:**
```javascript
bonus_unit = floor(qty_terjual ÷ 2)
bonus_amount = bonus_unit × Rp 5.000 (official) / Rp 4.000 (training)
```

**Contoh:**
```
Promotor Official jual Y02:
├─ 2 unit → floor(2÷2) = 1 unit → Rp 5.000
├─ 3 unit → floor(3÷2) = 1 unit → Rp 5.000 (sisa 1 unit diabaikan)
├─ 4 unit → floor(4÷2) = 2 unit → Rp 10.000
├─ 5 unit → floor(5÷2) = 2 unit → Rp 10.000
├─ 6 unit → floor(6÷2) = 3 unit → Rp 15.000
└─ 7 unit → floor(7÷2) = 3 unit → Rp 15.000

Promotor Training jual Y03T:
- 12 unit → floor(12÷2) = 6 unit → 6 × Rp 4.000 = Rp 24.000
```

---

### **C. BONUS BERJALAN (Real-Time Projection)**

**Konsep:** Bonus ditampilkan real-time, update setiap ada sales baru.

**Contoh Y02 (Rasio 2:1):**
```
Tanggal 1: Jual 1 unit Y02
└─ Total: 1 unit → Bonus: Rp 0 (belum 2 unit)

Tanggal 3: Jual 1 unit Y02 lagi
└─ Total: 2 unit → Bonus: Rp 5.000 (update!)

Tanggal 5: Jual 1 unit Y02 lagi
└─ Total: 3 unit → Bonus: Rp 5.000 (tetap, unit ke-3 belum berpasangan)

Tanggal 7: Jual 1 unit Y02 lagi
└─ Total: 4 unit → Bonus: Rp 10.000 (update!)

Dashboard selalu menampilkan akumulasi bulan berjalan.
```

---

### **D. TUNJANGAN (Terpisah dari Insentif)**

**Hanya untuk Promotor Official:**

| Achievement Bulan Ini | Tunjangan |
|-----------------------|-----------|
| < Rp 180 juta | Rp 0 |
| Rp 180 juta - Rp 249 juta | Rp 315.000 (Middle) |
| ≥ Rp 250 juta | Rp 815.000 (High) |

**Catatan:**
```
✅ Tunjangan TERPISAH dari insentif penjualan
✅ Dibayar bersamaan dengan bonus
✅ Harus ada detail breakdown di dashboard:
   "Tunjangan Middle Rp 315.000 (syarat: pencapaian Rp 180jt-249jt)"
```

---

### **E. TOTAL PENGHASILAN - UI BREAKDOWN**

```
┌─────────────────────────────────────────────────────┐
│ 💰 TOTAL PENGHASILAN - JANUARI 2026                │
│ Promotor A (Official) - Pencapaian: Rp 200.000.000     │
├─────────────────────────────────────────────────────┤
│                                                     │
│ 💵 KOMPENSASI TETAP                                │
│ ├─ Gaji Pokok: Rp 2.185.000                       │
│ └─ Tunjangan Middle: Rp 315.000                    │
│    (Syarat: Pencapaian Rp 180jt - Rp 249jt)            │
│    Subtotal: Rp 2.500.000                          │
│                                                     │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                                     │
│ 💎 INSENTIF PENJUALAN (DETAIL)                    │
│                                                     │
│ Range Rp 2.000.000 - Rp 2.999.999:                │
│ ├─ Y29: 6 unit × Rp 25.000 = Rp 150.000          │
│ ├─ Y21Ds: 4 unit × Rp 25.000 = Rp 100.000        │
│ └─ Subtotal: Rp 250.000                            │
│                                                     │
│ Range Rp 3.000.000 - Rp 3.999.999:                │
│ ├─ Y400: 5 unit × Rp 45.000 = Rp 225.000         │
│ ├─ V40: 3 unit × Rp 45.000 = Rp 135.000          │
│ └─ Subtotal: Rp 360.000                            │
│                                                     │
│ Produk Khusus (Rasio 2:1):                         │
│ ├─ Y02: 12 unit → 6 bonus × Rp 5.000 = Rp 30.000 │
│ │  Detail: 6 pasang (12 unit), sisa 0             │
│ └─ Subtotal: Rp 30.000                             │
│                                                     │
│ Bonus Cash (X Series):                              │
│ ├─ X300: 1 unit × Rp 250.000 = Rp 250.000        │
│ └─ Subtotal: Rp 250.000                            │
│                                                     │
│ Total Insentif: Rp 890.000                         │
│                                                     │
│ ✅ Syarat Minimum: Rp 120.000.000 TERPENUHI       │
│ ✅ INSENTIF AKAN DIBAYAR                          │
│                                                     │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                                     │
│ 🎯 TOTAL PENGHASILAN: Rp 3.390.000                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 📋 PART 2: ALERT SYSTEM (MONITORING STATUS PROMOTOR)

### **A. ALERT 1: Kandidat Official (Training → Official)** 🟢

**Trigger:**
```
✅ Status: Promotor Training
✅ Pencapaian 2 bulan berturut ≥ Rp 120.000.000
```

**Alert Message:**
```
⭐ KANDIDAT OFFICIAL

Promotor A sudah 2 bulan berturut mencapai ≥ Rp 120 juta:
├─ November: Rp 125.000.000 ✅
└─ Desember: Rp 130.000.000 ✅

Sisa 1 bulan lagi untuk eligible jadi Promotor Official.
Silakan persiapkan ujian Official.
```

**Alert Saat 3 Bulan:**
```
🎉 ELIGIBLE OFFICIAL!

Promotor A sudah 3 bulan berturut ≥ Rp 120 juta:
├─ November: Rp 125.000.000 ✅
├─ Desember: Rp 130.000.000 ✅
└─ Januari: Rp 140.000.000 ✅

Promotor A eligible untuk ujian Official!
Koordinasi dengan HRD untuk jadwal ujian.
```

**Siapa yang Dapat Alert:**
- ✅ Promotor itu sendiri (dashboard pribadi)
- ✅ SATOR yang handle promotor (notifikasi)
- ✅ SPV (notifikasi)
- ✅ Manager Area (dashboard summary)
- ✅ Admin/HRD (alert center)

---

### **B. ALERT 2: Warning Downgrade (Official → Training)** 🔴

**Trigger:**
```
⚠️ Status: Promotor Official
⚠️ Pencapaian 2 bulan berturut < Rp 120.000.000
```

**Alert Message:**
```
⚠️ WARNING: RISIKO DOWNGRADE

Promotor B sudah 2 bulan berturut di bawah Rp 120 juta:
├─ November: Rp 110.000.000 ❌ (kurang Rp 10 juta)
└─ Desember: Rp 105.000.000 ❌ (kurang Rp 15 juta)

Jika Januari < Rp 120 juta, akan DOWNGRADE ke Training.
Progress bulan ini: Rp 85.000.000 (kekurangan Rp 35 juta)
```

**Alert Saat 3 Bulan:**
```
❌ ACTION REQUIRED: DOWNGRADE TO TRAINING

Promotor B sudah 3 bulan berturut < Rp 120 juta:
├─ November: Rp 110.000.000 ❌
├─ Desember: Rp 105.000.000 ❌
└─ Januari: Rp 100.000.000 ❌

⚠️ INSTRUKSI: Admin update status ke Training dari User Management.
```

**Siapa yang Dapat Alert:**
- ✅ Promotor itu sendiri (warning dashboard)
- ✅ SATOR yang handle (prioritas tinggi)
- ✅ SPV (action required)
- ✅ Manager Area (supervisor)
- ✅ Admin/HRD (untuk proses downgrade)

---

### **C. Alert Center UI**

```
┌─────────────────────────────────────────────────────┐
│ 🔔 ALERT CENTER - STATUS PROMOTOR                  │
├─────────────────────────────────────────────────────┤
│                                                     │
│ 🟢 KANDIDAT OFFICIAL (3)                            │
│ ├─ Promotor A (Tim Antonio) - 2 bulan ✅          │
│ │  Nov: 125jt, Des: 130jt, Jan: 95jt (tracking)   │
│ ├─ Promotor C (Tim Andri) - 3 bulan ✅ ELIGIBLE!  │
│ │  Nov: 140jt, Des: 135jt, Jan: 145jt             │
│ └─ Promotor D (Tim Antonio) - 2 bulan ✅          │
│    Nov: 122jt, Des: 128jt, Jan: 110jt (tracking)   │
│                                                     │
│ 🔴 WARNING DOWNGRADE (2)                            │
│ ├─ Promotor B (Tim Antonio) - 2 bulan ❌          │
│ │  Nov: 110jt, Des: 105jt, Jan: 95jt (tracking)   │
│ └─ Promotor E (Tim Andri) - 3 bulan ❌ ACTION!    │
│    Nov: 100jt, Des: 98jt, Jan: 105jt              │
│    ⚠️ Admin: Update status ke Training            │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Key Points:**
```
❌ TIDAK ADA AUTO DOWNGRADE/UPGRADE
✅ HANYA ALERT & REMINDER
✅ Admin manual update dari User Management
✅ Sistem hanya tracking & notifikasi
```

---

## 📋 PART 3: BONUS SATOR

### **A. DUA JENIS BONUS SATOR**

#### **1. BONUS POIN (Range-Based)**

**Sistem KPI (4 Kategori Penilaian):**

| Kategori | Bobot | Max Achievement |
|----------|-------|-----------------|
| Sell Out All Type | 40% | 100% = 40% |
| Sell Out Produk Fokus | 30% | 100% = 30% |
| Sell In All Type | 20% | 100% = 20% |
| KPI Manager Area | 0-10% | Variable per SATOR |

**Syarat Cair:**
```
Total Achievement ≥ 80%

Contoh:
Antonio - Januari:
├─ Sell Out All: 90% → 90% × 40% = 36%
├─ Sell Out Fokus: 85% → 85% × 30% = 25.5%
├─ Sell In: 80% → 80% × 20% = 16%
└─ KPI MA: 5% (dari Manager)
Total: 36 + 25.5 + 16 + 5 = 82.5% ✅ (≥ 80%, CAIR!)

Andri - Januari:
├─ Sell Out All: 70% → 28%
├─ Sell Out Fokus: 75% → 22.5%
├─ Sell In: 65% → 13%
└─ KPI MA: 7%
Total: 70.5% ❌ (< 80%, TIDAK CAIR!)
```

**Poin Insentif (1 Poin = Rp 1.000):**

| Range Harga (SRP) | Poin/Unit |
|-------------------|-----------|
| Rp 1.000.000 - Rp 1.399.999 | 0.7 |
| Rp 1.400.000 - Rp 1.899.999 | 1.5 |
| Rp 1.999.000 - Rp 2.499.999 | 2.0 |
| Rp 2.500.000 - Rp 2.999.999 | 2.5 |
| Rp 3.000.000 - Rp 3.499.999 | 4.5 |
| Rp 3.500.000 - Rp 3.999.999 | 8.0 |
| Rp 4.000.000 - Rp 4.499.999 | 10.0 |
| Rp 4.500.000 - Rp 5.999.999 | 14.0 |
| > Rp 6.000.000 | 18.0 |

**Contoh Perhitungan:**
```
SATOR Antonio - Sell Out All Type Januari:
├─ Y29 (Rp 2.8jt): 30 unit × 2.5 poin = 75 poin
├─ Y400 (Rp 3.5jt): 45 unit × 8.0 poin = 360 poin
├─ V60 (Rp 4.2jt): 25 unit × 10.0 poin = 250 poin
└─ Total: 685 poin

Insentif Poin: 685 × Rp 1.000 = Rp 685.000

TAPI! Ini baru komponen Sell Out All (40%)
Achievement Sell Out All: 90% (dari target)
Kontribusi ke total: Rp 685.000 × 90% = Rp 616.500

(Ditambah Sell Out Fokus, Sell In, KPI MA untuk total insentif)
```

**Sanksi:**
```
❌ TIDAK ADA DENDA untuk Bonus Poin
✅ Jika Total Achievement < 80% → Bonus Poin = Rp 0
```

---

#### **2. BONUS REWARD KHUSUS (Produk Tertentu)**

**Produk dengan Reward (Desember 2025):**
- Y400 Series
- Y21Ds / Y29s
- V60 Lite Series

**SYARAT REWARD:**
```
1. Achievement produk = 100% (EXACT atau LEBIH)
2. Skala berdasarkan ACTUAL unit terjual

Contoh:
Target Y400: 40 unit
Actual Y400: 55 unit (137.5%) ✅

✅ Syarat 1: 137.5% ≥ 100% → TERPENUHI
✅ Syarat 2: Actual 55 unit → Skala > 50 unit
✅ Reward: Rp 1.250.000
```

**Tabel Reward:**

**Y400 Series:**
| Actual Unit | Reward |
|-------------|--------|
| < 30 unit | Rp 500.000 |
| 30 - 50 unit | Rp 750.000 |
| > 50 unit | Rp 1.250.000 |

**Y21Ds / Y29s:**
| Actual Unit | Reward |
|-------------|--------|
| < 50 unit | Rp 500.000 |
| 50 - 80 unit | Rp 1.250.000 |
| > 80 unit | Rp 1.500.000 |

**V60 Lite Series:**
| Actual Unit | Reward |
|-------------|--------|
| < 20 unit | Rp 600.000 |
| 20 - 50 unit | Rp 800.000 |
| > 50 unit | Rp 1.500.000 |

**Contoh Lengkap:**
```
SATOR Antonio - Januari:

Target Y400: 50 unit
Actual Y400: 35 unit (70%) ❌
├─ Achievement: 70% < 100% → TIDAK DAPAT REWARD
├─ Achievement: 70% < 80% → DENDA Rp 100.000
└─ Result: -Rp 100.000

Target Y29: 60 unit
Actual Y29: 60 unit (100%) ✅
├─ Achievement: 100% → DAPAT REWARD
├─ Actual: 60 unit → Skala 50-80 → Rp 1.250.000
└─ Result: +Rp 1.250.000

Target V60 Lite: 30 unit
Actual V60 Lite: 25 unit (83.3%) ✅
├─ Achievement: 83.3% < 100% → TIDAK DAPAT REWARD
├─ Achievement: 83.3% ≥ 80% → TIDAK DENDA
└─ Result: Rp 0

TOTAL REWARD KHUSUS: Rp 1.250.000 - Rp 100.000 = Rp 1.150.000
```

**Sanksi/Denda:**
```
⚠️ Jika achievement produk < 80%
Denda: Rp 100.000 per produk

Contoh:
- Y400: 70% ❌ → Denda Rp 100.000
- Y29: 100% ✅ → No denda
- V60: 65% ❌ → Denda Rp 100.000
Total Denda: Rp 200.000
```

---

### **B. KPI MANAGER AREA (Individual per SATOR)**

```
Admin UI - Bonus Settings:
┌────────────────────────────────────────────────────┐
│ KPI MANAGER AREA - Per SATOR                       │
├────────────────────────────────────────────────────┤
│                                                     │
│ SATOR Antonio:                                     │
│ └─ KPI MA Bobot: [___5___] %                      │
│    Default: 5%, Range: 0-10%                       │
│                                                     │
│ SATOR Andri:                                       │
│ └─ KPI MA Bobot: [___7___] %                      │
│    Default: 5%, Range: 0-10%                       │
│                                                     │
│ Note: Individual assessment dari Manager Area      │
│       untuk setiap SATOR                           │
└────────────────────────────────────────────────────┘

SATOR Dashboard (Antonio - View Only):
├─ Sell Out All Type: 40%
├─ Sell Out Fokus: 30%
├─ Sell In All Type: 20%
├─ KPI MA: 5% (dari Manager Area)
└─ Total Bobot Maksimal: 95%
```

**Key Points:**
```
✅ KPI MA BERBEDA per SATOR (individual assessment)
✅ Default value: 5%
✅ Range: 0% - 10%
✅ Admin yang atur (bukan SATOR sendiri)
✅ SATOR hanya bisa view (tidak bisa edit)
```

---

## 🔧 ADMIN CONTROL REQUIREMENTS

### **A. Bonus Settings (Global)**

```
1. RANGE-BASED BONUS (Promotor)
   ├─ Edit range harga (min-max)
   ├─ Edit bonus Official per range
   ├─ Edit bonus Training per range
   ├─ Add new range
   └─ Delete range

2. FLAT BONUS CASH (X Series)
   ├─ Add produk baru (X500, dll)
   ├─ Edit bonus amount
   ├─ Active/Inactive
   └─ Periode berlaku

3. RASIO BONUS (Y02/Y03T/Y04S)
   ├─ Add produk baru dengan rasio
   ├─ Edit rasio (default 2:1)
   ├─ Edit bonus per unit
   └─ Active/Inactive

4. TUNJANGAN (Promotor Official)
   ├─ Edit threshold Middle (Rp 180-249jt)
   ├─ Edit threshold High (≥ Rp 250jt)
   ├─ Edit amount Middle (Rp 315k)
   └─ Edit amount High (Rp 815k)

5. SYARAT MINIMUM PENCAPAIAN
   ├─ Edit minimal Training (Rp 60jt)
   └─ Edit minimal Official (Rp 120jt)

6. SATOR POIN
   ├─ Edit range harga
   ├─ Edit poin per range
   └─ Add new range

7. SATOR REWARD KHUSUS
   ├─ Add produk reward (dynamic)
   ├─ Edit skala unit
   ├─ Edit reward amount
   ├─ Edit denda amount
   ├─ Periode berlaku (bulan/tahun)
   └─ Active/Inactive

8. KPI BOBOT
   ├─ Edit bobot Sell Out All (default 40%)
   ├─ Edit bobot Sell Out Fokus (default 30%)
   ├─ Edit bobot Sell In (default 20%)
   ├─ Edit threshold cair (default 80%)
   └─ Edit KPI MA per SATOR (0-10%)

9. ALERT THRESHOLDS
   ├─ Edit berapa bulan untuk alert (default 2)
   ├─ Edit berapa bulan untuk eligible (default 3)
   └─ Enable/Disable alert per kategori
```

### **B. User Management (Manual Status Update)**

```
Admin Manually Update:
1. Promotor Status (Training ↔ Official)
   ├─ Update status
   ├─ Update gaji pokok
   ├─ Update target standar
   └─ Auto-adjust insentif rate

2. SATOR Status
   ├─ Assign promotor
   ├─ Set KPI MA bobot individual
   └─ Active/Inactive

3. Data Override
   ├─ Manual edit pencapaian (kalau ada koreksi)
   ├─ Manual edit target
   └─ History log (who, when, why)
```

---

## 💾 DATABASE DESIGN IMPLICATIONS

### **Key Tables Needed:**

```sql
-- Bonus Range Settings
bonus_ranges (
  id, type (promotor_official/promotor_training/sator_poin),
  price_min, price_max, bonus_amount, active, created_at
)

-- Flat Bonus Cash
bonus_flat_cash (
  id, product_name, bonus_amount, official_only, 
  active, start_date, end_date
)

-- Rasio Bonus
bonus_ratio (
  id, product_name, ratio_divider (default 2), 
  bonus_official, bonus_training, active
)

-- SATOR Reward Khusus (Dynamic)
sator_rewards (
  id, period (2025-12), product_name (Y400/Y29/V60),
  target_achievement (100%), 
  scale_min, scale_max, reward_amount, denda_amount,
  active, created_at
)

-- KPI MA per SATOR
sator_kpi_ma (
  id, sator_id, period (2026-01), 
  kpi_bobot (0-10%), set_by_admin_id, updated_at
)

-- Alert Tracking
promotor_alert_tracking (
  id, promotor_id, alert_type (kandidat_official/warning_downgrade),
  streak_months, last_check_date, status (active/resolved)
)

-- Bonus Calculation History
bonus_calculations (
  id, user_id, period, type (promotor/sator),
  detail_json (breakdown lengkap), 
  total_amount, paid (boolean), paid_date
)
```

---

## 🎯 SUMMARY: LOCKED RULES

### **Promotor:**
```
✅ 2 Tipe: Official vs Training
✅ 3 Jenis Insentif: Range-based, Flat Cash, Rasio 2:1
✅ Syarat Minimum: Rp 60jt (Training), Rp 120jt (Official)
✅ Tunjangan: Middle (Rp 315k), High (Rp 815k)
✅ Bonus Berjalan: Real-time projection
✅ Detail Breakdown: Per produk × qty × bonus
❌ Bonus Masa Kerja: SKIP (tidak dimasukkan)
```

### **Alert System:**
```
✅ Kandidat Official: 2 bulan ≥ Rp 120jt
✅ Warning Downgrade: 2 bulan < Rp 120jt
✅ Eligible/Action: 3 bulan
❌ NO AUTO-PROCESS (manual admin update)
✅ Alert ke: Promotor, SATOR, SPV, Manager, Admin
```

### **SATOR:**
```
✅ 2 Jenis Bonus: Poin (range-based) + Reward Khusus
✅ KPI 4 Kategori: 40%-30%-20%-(0-10%)
✅ KPI MA: Individual per SATOR (default 5%)
✅ Syarat Cair: Total ≥ 80%
✅ Reward: Achievement 100% + Skala actual unit
✅ Denda: Rp 100k per produk < 80%
```

### **Admin Control:**
```
✅ Full flexibility (semua aturan bisa diubah)
✅ Dynamic product rewards
✅ Individual SATOR KPI MA
✅ Manual status update
✅ History tracking
```

---

---

## 📋 PART 4: BONUS SPV AREA

### **A. DUA JENIS BONUS SPV**

#### **1. BONUS POIN (Range-Based)**

**Sistem KPI (4 Kategori Penilaian):**

| No | Jenis Penilaian | Bobot | Kategori % |
|----|-----------------|-------|------------|
| 1 | Sell Out All Type (Value) | 40% | A |
| 2 | Sell In All Type (Value) | 30% | B |
| 3 | Sell Out Produk Fokus (Unit) | 20% | C |
| 4 | KPI MA | 10% | D |
| | **TOTAL** | **100%** | |

**Perhitungan Bobot (Based on Achievement):**
- Achievement 100% → Dapat FULL Bobot (e.g., 40%)
- Achievement 80% → Dapat (Bobot × 0.8)
- Achievement 60% → Dapat (Bobot × 0.6)
- Achievement 10% → Dapat (Bobot × 0.1)

**Syarat Cair:**
```
Total Persentase Penilaian Minimal 80%
(Jumlah A + B + C + D ≥ 80%)

Jika < 80% → Insentif tidak cair (Rp 0).
```

**Poin Insentif (1 Poin = Rp 1.000):**
Berdasarkan **Unit Sell Out All Type**.

| Range Harga (SRP) | Poin/Unit (SPV) |
|-------------------|-----------------|
| Rp 1.000 - Rp 1.399 | 0.6 |
| Rp 1.400 - Rp 1.899 | 0.8 |
| Rp 1.999 - Rp 2.499 | 1.5 |
| Rp 2.500 - Rp 2.999 | 2.0 |
| Rp 3.000 - Rp 3.499 | 4.0 |
| Rp 3.500 - Rp 3.999 | 6.0 |
| Rp 4.000 - Rp 4.499 | 8.0 |
| Rp 4.500 - Rp 5.999 | 12.0 |
| > Rp 6.000 | 14.0 |

**Contoh Perhitungan:**
```
SPV Gery - Desember:
1. Hitung Total % KPI:
   - Sell Out All (40%): Achieve 90% → 36%
   - Sell In All (30%): Achieve 100% → 30%
   - Sell Out Fokus (20%): Achieve 70% → 14%
   - KPI MA (10%): Achieve 100% → 10%
   TOTAL = 36 + 30 + 14 + 10 = 90% ✅ (CAIR!)

2. Hitung Total Poin:
   - Y29 (2.5jt): 300 unit × 1.5 = 450 poin
   - V60 (4jt): 100 unit × 8.0 = 800 poin
   - dst...
   TOTAL POIN = 5000 poin
   TOTAL RUPIAH = 5000 × Rp 1.000 = Rp 5.000.000

3. Final Amount:
   Rp 5.000.000
```

---

#### **2. BONUS REWARD KHUSUS (SPV)**

**Produk dengan Reward (Desember 2025):**
Bersifat dynamic, bisa berubah tiap bulan.

**A. V400 Series (Sell Out)**
- Indikator: Achievement 100%

| Skala Unit | Reward SPV |
|------------|------------|
| < 50 unit | Rp 750.000 |
| 50 - 80 unit | Rp 1.000.000 |
| > 80 unit | Rp 1.250.000 |

**B. Y21Ds / Y29s (Sell Out)**
- Indikator: Achievement 100%

| Skala Unit | Reward SPV |
|------------|------------|
| < 80 unit | Rp 600.000 |
| 80 - 150 unit | Rp 1.250.000 |
| > 150 unit | Rp 1.500.000 |

**C. V60 Lite Series (Sell Out)**
- Indikator: Achievement 100%

| Skala Unit | Reward SPV |
|------------|------------|
| < 40 unit | Rp 600.000 |
| 40 - 80 unit | Rp 1.200.000 |
| > 80 unit | Rp 1.500.000 |

**Catatan:**
- Syarat UTAMA adalah **Achievement 100%**.

**Sanksi/Denda (Reward Khusus):**
```
⚠️ Jika pencapaian SETIAP kategori penilaian < 80% (per produk)
Denda: Rp 150.000 per kategori penilaian

Contoh:
- V400: Achieve 70% ❌ (< 80%) → Denda Rp 150.000
- Y29s: Achieve 100% ✅ (≥ 80%) → No Denda (Dapat Reward)
- V60: Achieve 85% ✅ (≥ 80%) → No Denda (No Reward karena < 100%)

Total Denda: Rp 150.000
Potong dari total bonus yang diterima.
```

---

### **B. ADMIN REQUIREMENTS (SPV BONUS)**

```
1. KPI BOBOT SPV
   ├─ Edit bobot per kategori (40/30/20/10)
   └─ Edit threshold cari (80%)

2. SPV POIN
   ├─ Edit range harga
   ├─ Edit poin per range
   └─ Add/Delete range

3. SPV REWARD KHUSUS
   ├─ Add produk reward
   ├─ Edit skala unit
   ├─ Edit reward amount
   └─ Dynamic per periode
```

---

**STATUS:** 100% FINALIZED & READY FOR IMPLEMENTATION ✅  
**Next:** Database Schema Design + UI Mockups
