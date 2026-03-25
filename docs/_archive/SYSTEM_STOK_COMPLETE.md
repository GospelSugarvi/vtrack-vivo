# 📦 ANALISIS LENGKAP: SISTEM STOK (INVENTORY MANAGEMENT)

**Berdasarkan:** Sistem yang sudah ada (Django)  
**Tujuan:** Dokumentasi untuk rebuild Flutter app  
**Tanggal:** 2 Januari 2026

---

## 🎯 OVERVIEW: SISTEM STOK 3-LAYER

Sistem stok memiliki **3 layer** yang berbeda dengan tujuan berbeda:

```
┌─────────────────────────────────────────┐
│  LAYER 1: STOK TOKO (Promotor)          │
│  - Input stok masuk per IMEI            │
│  - Track barang di toko per unit        │
│  - Tipe: Display, Ready, Transit, Chip  │
└─────────────────────────────────────────┘
           ↓ Daily Report ↓
┌─────────────────────────────────────────┐
│  LAYER 2: STOK GUDANG (SATOR/Sales)     │
│  - Input stok di gudang pusat           │
│  - Per model (bukan per IMEI)           │
│  - Status: Cukup, Tipis, Kosong         │
└─────────────────────────────────────────┘
           ↓ Reference for ↓
┌─────────────────────────────────────────┐
│  LAYER 3: STOK READY (SATOR/Sales)      │
│  - Track stok siap jual di toko         │
│  - Used for restock planning            │
│  - Alert kalau stok < minimal           │
└─────────────────────────────────────────┘
```

---

## 📊 DATABASE MODELS

### **1. Stok (Layer 1 - Per Toko)**
**File:** `bot_logic/models.py` - Model `Stok`

```python
class Stok(models.Model):
    id = BigAutoField(primary_key=True)
    produk = ForeignKey(Produk)
    promotor = ForeignKey(Pengguna)
    toko = ForeignKey(Toko)
    imei = CharField(unique=True, max_length=255)  # ✅ Unique identifier!
    created_at = DateTimeField()
    tipe_stok = CharField(max_length=255)  # ⬅️ KEY FIELD
    
    # Indexes for performance
    indexes = [
        Index(['toko', 'produk']),
        Index(['toko', 'created_at']),
        Index(['promotor', 'created_at']),
    ]
```

**Tipe Stok:**
```
1. "Display" = Produk untuk dipajang di toko (demo unit)
2. "Ready"   = Produk siap jual (sealed box)
3. "Transit" = Produk dalam perjalanan ke toko
4. "Chip"    = Produk second/bekas (dijual kembali)
```

**Use Case:**
- Promotor scan IMEI barcode → save to stok
- Tracking individual unit movement
- Audit trail per produk
- Prevent duplicate IMEI (fraud detection)

---

### **2. StokGudangHarian (Layer 2 - Gudang Pusat)**
**File:** `bot_logic/models.py` - Model `StokGudangHarian`

```python
class StokGudangHarian(models.Model):
    id = BigAutoField(primary_key=True)
    produk = ForeignKey(Produk)
    nama_model = CharField(max_length=255)
    varian_ram_rom = CharField(max_length=255)
    warna = CharField(max_length=255)
    harga_srp = IntegerField()
    harga_modal = IntegerField(null=True)
    seri_produk = ForeignKey(SeriProduk)
    
    # 📦 STOCK COUNTS (Per Model, NOT per IMEI):
    stok_gudang = IntegerField(default=0)  # Stock di gudang
    stok_otw = IntegerField(default=0)     # On The Way (transit)
    
    # 📅 TIME & STATUS:
    tanggal = DateField()                  # Date of record
    created_at = DateTimeField()
    status = CharField(max_length=20, default='kosong')  # kosong/tipis/cukup
    created_by = ForeignKey(Pengguna, null=True)  # Who input this
```

**Status Logic:**
```python
def calculate_stok_gudang_status(harga_srp, stok_gudang):
    if stok_gudang == 0:
        return 'kosong'
    elif harga_srp <= 1999000:
        return 'tipis' if stok_gudang < 100 else 'cukup'
    elif 2000000 <= harga_srp <= 2999000:
        return 'tipis' if stok_gudang <= 50 else 'cukup'
    elif 3000000 <= harga_srp <= 5000000:
        return 'tipis' if stok_gudang <= 20 else 'cukup'
    else: # harga_srp > 5000000
        return 'tipis' if stok_gudang <= 10 else 'cukup'
```

**Logic Explained:**
- **Produk murah** (<2jt): Perlu stok banyak (100+ = cukup)
- **Produk mid-range** (2-3jt): Stok sedang (50+ = cukup)
- **Produk premium** (3-5jt): Stok sedikit OK (20+ = cukup)
- **Produk flagship** (>5jt): Very low stock OK (10+ = cukup)

**Use Case:**
- SATOR input stok gudang harian (pagi/siang)
- Reference untuk order decision
- Tracking inventory level over time
- Generate restocking alerts

---

### **3. StokReady (Layer 3 - Ready to Sell)**
**File:** `bot_logic/models.py` - Model `StokReady` (referenced in views)

```python
# Tidak ada di models.py yang di-view, tapi referenced di code
class StokReady(models.Model):
    produk = ForeignKey(Produk)
    toko = ForeignKey(Toko)
    stok_tersedia = IntegerField()  # Available stock
    stok_otw = IntegerField()       # On the way
    status = CharField()            # kosong/tipis/cukup
```

**Use Case:**
- Monitor stok ready per toko
- Alert kalau < stok minimal
- Used by rekomendasi order system
- SATOR view all toko status

---

### **4. LaporanStokToko (Tracking & Assignment)**
**File:** `bot_logic/models.py` - Model `LaporanStokToko`

```python
class LaporanStokToko(models.Model):
    toko = ForeignKey(Toko)
    tanggal = DateField()
    status = BooleanField(default=False)  # True = sudah laporan
    petugas = ForeignKey(Pengguna, null=True)  # Promotor yang ditunjuk
    waktu_laporan = DateTimeField(null=True)
    catatan = TextField(null=True)
    
    unique_together = ('toko', 'tanggal')  # One report per toko per day
```

**Use Case:**
- Track siapa yang sudah/belum laporan stok
- Assignment system (SATOR tunjuk promotor)
- Accountability tracking
- Daily checklist for promotor

---

## 📱 WORKFLOW LENGKAP

### **MORNING (07:00-09:00): Stock Check**

#### **Promotor:**
```
1. Buka app → "Laporan Stok"
   
2. Pilih kondisi:
   ○ Tidak ada barang masuk
   ⦿ Ada barang baru
   ○ Barang cuci gudang
   ○ Barang chip (second)

3. IF "Ada barang baru":
   a. Pilih produk dari list
   b. Scan IMEI barcode (multiple)
      - Y19s 8/128: [scan] [scan] [scan] (3 unit)
      - V40 12/256: [scan] [scan] (2 unit)
   
   c. System auto-save:
      - Save ke tabel `stok`
      - tipe_stok = "ready" (default)
      - IMEI unique validation
   
   d. Send notification Discord:
      "Ahmad (Transmart MTC) input 5 unit stok baru:
       - Y19s: 3 unit
       - V40: 2 unit"

4. IF "Tidak ada barang":
   - Save to `laporan_stok_toko`:
     status = True
     catatan = "Tidak ada barang masuk"
   
   - Discord notification:
     "Ahmad (MTC): Tidak ada stok masuk hari ini"

5. IF "Cuci Gudang":
   - Input manual (non-standard product):
     Nama: [Y19 Ex Display]
     Varian: [8+128]
     Warna: [Black]
     Harga Khusus: [Rp 1,800,000]
     IMEI: [scan multiple]
   
   - Save to `cuci_gudang` table (separate!)
   
6. IF "Chip" (Barang Second):
   - Similar to "Ada barang baru"
   - But tipe_stok = "chip"
   - Harga bisa lebih murah
```

#### **SATOR/Sales:**
```
1. Buka app → "Input Stok Gudang"

2. Upload screenshot atau input manual:
   
   Method 1: Upload Image (AI-powered)
   ┌─────────────────────────────────┐
   │ 📷 Drop screenshot here         │
   │                                 │
   │ Gemini AI will auto-detect:     │
   │ - Product name                  │
   │ - Stock qty                     │
   │ - OTW qty                       │
   └─────────────────────────────────┘
   
   → API: /api/stok-gudang/parse-image/
   → Gemini parse image → return JSON
   
   Method 2: Manual Input
   ┌────────────────────────────────────┐
   │ Produk           │ Gudang │  OTW  │
   ├──────────────────┼────────┼───────┤
   │ Y19s 8/128 Black │  [50]  │  [10] │
   │ V40 12/256 Gold  │  [20]  │  [0]  │
   │ Y400 6/128 Black │  [5]   │  [15] │
   │ [+ Add Product]              │
   └──────────────────────────────────┘

3. System auto-calculate status:
   - Y19s (harga 2.5jt, stok 50): "Tipis" ⚠️
   - V40 (harga 4.5jt, stok 20): "Cukup" ✅
   - Y400 (harga 2.2jt, stok 5): "Kosong" ❌

4. Preview & Save:
   [Preview Image] → Generate visual card
   [Save to Database] → Bulk insert to `stok_gudang_harian`
   [Send to Discord] → Notification to team

5. Database logic:
   - If record exists for today → UPDATE
   - If not exists → INSERT
   - Bulk operation (efficient!)
```

---

### **Display vs Ready vs Transit**

```
SCENARIO: Promotor scan IMEI

┌─────────────────────────────────────────┐
│  Scan IMEI: 123456789012345             │
│                                         │
│  Produk detected: Y19s 8/128GB Black    │
│                                         │
│  Tipe Stok:                             │
│  ⦿ Display (Untuk pajang)               │
│  ○ Ready (Siap jual)                    │
│  ○ Transit (Dalam perjalanan)           │
│                                         │
│  [Submit]                               │
└─────────────────────────────────────────┘

Database:
{
  "imei": "123456789012345",
  "produk_id": 42,
  "toko_id": 1,
  "promotor_id": 5,
  "tipe_stok": "display",  ← Saved!
  "created_at": "2026-01-02 08:30:00"
}
```

**Use Cases per Type:**

**1. Display:**
```
Purpose: Demo unit di toko
- Untuk customer coba/lihat
- Tidak dijual (kecuali clearance)
- Tracking: 1 toko biasanya 1-2 unit display per model
```

**2. Ready:**
```
Purpose: Produk sealed, siap dijual
- Main inventory untuk penjualan
- Tracking: Per toko bisa 5-20 unit
- Alert kalau < 3 unit (perlu restock)
```

**3. Transit:**
```
Purpose: Barang sudah dikirim, belum sampai
- Status sementara
- Auto-update jadi "ready" saat terima barang
- Expected arrival date tracking
```

**4. Chip (Second/Bekas):**
```
Purpose: Barang ex-display atau return
- Harga lebih murah
- Separate tracking (tidak campur dengan fresh)
- Special pricing rules
```

---

## 🔄 STOCK MOVEMENT FLOW

### **Fresh Stock Journey:**

```
1. ARRIVAL (Promotor Action):
   ┌─────────────┐
   │ Scan IMEI   │ → Save to `stok`
   │ tipe: ready │    (Individual unit)
   └─────────────┘

2. DAILY SUMMARY (SATOR Action):
   ┌──────────────────┐
   │ Input Stok Gudang│ → Save to `stok_gudang_harian`
   │ Y19s: 50 unit    │    (Aggregate count)
   └──────────────────┘

3. SOLD (Promotor Action):
   ┌──────────────┐
   │ Scan IMEI    │ → Delete from `stok`?
   │ untuk jualan │    OR mark as sold?
   └──────────────┘
   
   ⚠️ **CRITICAL**: Dari code, saya tidak lihat
   stok berkurang saat jualan!
   
   Apakah:
   a) Stok auto-decrement saat jualan?
   b) Manual adjustment?
   c) Atau periodic reconciliation?
```

### **Stock Reconciliation:**

```
┌─────────────────────────────────────────┐
│  PROBLEM: Mismatch Data                 │
├─────────────────────────────────────────┤
│                                         │
│  Stok Gudang (SATOR input):             │
│  Y19s = 50 unit                         │
│                                         │
│  Stok Toko (Promotor scan IMEI):        │
│  Y19s = 12 IMEI records                 │
│                                         │
│  ❓ Which one is correct?               │
│                                         │
│  Solution options:                      │
│  1. Gudang = Source of truth            │
│  2. IMEI count = Source of truth        │
│  3. Daily reconciliation process        │
│                                         │
└─────────────────────────────────────────┘
```

**⚠️ CATATAN PENTING:**
Dari analisis code, saya **tidak menemukan** logic untuk:
- Auto-decrement stok saat penjualan
- Reconciliation between `stok` dan `stok_gudang`
- Stock movement tracking

Ini **potential issue** yang perlu di-clarify!

---

## 📸 SPECIAL FEATURES

### **1. AI Image Parsing (Gemini)**

**File:** `stok_gudang_views.py` - `parse_stok_gudang_image_view()`

**Workflow:**
```
1. SATOR upload screenshot stok gudang
   (biasanya dari Excel/WhatsApp)

2. API upload image → Gemini 2.5 Flash

3. Gemini AI extract data:
   Input: PNG/JPG image
   Output: JSON
   [
     {"Produk": "Y19s 8/128 Black", "Stok": 50, "OTW": 10},
     {"Produk": "V40 12/256 Gold", "Stok": 20, "OTW": 0},
     ...
   ]

4. Auto-parse name to components:
   "Y19s 8/128 Black" →
   - nama_model: "Y19s"
   - varian: "8+128"
   - warna: "Black"

5. Match to database → Calculate status → Save

6. Show preview table for confirmation
```

**Regex Patterns:**
```python
# Two-parenthesis: iQOO Neo 10 (16+512G) (ORANGE)
r'^(.*?)\s+\((.*?)\)\s+\((.*?)\)$'

# Single-parenthesis: Y19S PRO 6+128G (SILVER)
r'^(.*?)\s+([0-9]+\+[0-9]+G?)\s+\((.*?)\)$'

# Fallback: Parse by spaces
```

**Benefits:**
- ✅ Save time (no manual typing)
- ✅ Reduce errors
- ✅ Consistent format
- ✅ Fast daily input (1-2 min instead of 15 min!)

---

### **2. Auto Status Calculation**

**Logic Table:**

| Harga Produk | Stok Cukup | Stok Tipis | Stok Kosong |
|--------------|------------|------------|-------------|
| <= 2jt       | >= 100     | 1-99       | 0           |
| 2-3jt        | >= 50      | 1-49       | 0           |
| 3-5jt        | >= 20      | 1-19       | 0           |
| > 5jt        | >= 10      | 1-9        | 0           |

**Why different thresholds?**
```
Produk Murah (Y-series):
- Fast moving (high demand)
- Perlu stok banyak
- Safety stock: 100 unit

Produk Mid (V-series):
- Moderate demand
- Stok sedang cukup
- Safety stock: 50 unit

Produk Premium (X-series, iQOO):
- Slow moving (niche market)
- Stok sedikit OK
- Safety stock: 10-20 unit
```

---

### **3. Restocking Alert System**

**File:** `stok_ready_views.py` - `restok_reminder_view()`

**Logic:**
```
1. Define stok minimal per produk per toko:
   Table: `stok_minimal_toko`
   - Y19s @ MTC: min 5 unit
   - V40 @ MTC: min 3 unit

2. Daily check (auto or manual):
   Compare actual_stock vs min_stock

3. If actual < minimal:
   ┌──────────────────────────────────┐
   │ ⚠️ RESTOCKING ALERT              │
   ├──────────────────────────────────┤
   │ Toko: Transmart MTC              │
   │ Produk: Y19s 8/128GB             │
   │ Stok Minimal: 5 unit             │
   │ Stok Sekarang: 2 unit   (❌ Low)│
   │ Kekurangan: 3 unit               │
   │                                  │
   │ [Generate Rekomendasi Order]     │
   └──────────────────────────────────┘

4. Auto-generate order recommendation:
   - Based on sales velocity (7 days avg)
   - Add safety buffer
   - Consider OTW stock
```

---

### **4. Cuci Gudang (Clearance) Tracking**

**Separate Table:** `cuci_gudang`

**Why separate?**
```
1. Different pricing (discounted)
2. Different product specs (might be ex-display)
3. Not standard inventory
4. Special tracking for accounting
5. Limited quantity (clearance sale)
```

**Workflow:**
```
Promotor:
1. Select "Cuci Gudang" pada laporan stok
2. Input manual (bukan dari master produk):
   - Nama model (free text!)
   - Varian (free text!)
   - Warna
   - Harga khusus (lower than SRP)
   - IMEI (scan multiple)

3. Save to `cuci_gudang` table

4. Notification Discord:
   "🔥 CUCI GUDANG
   Ahmad (MTC) input 5 unit clearance:
   - Y19 Ex Display 8/128: Rp 1.8jt (3 unit)
   - V40 Gores Halus: Rp 3.5jt (2 unit)"
```

---

## 📊 SATOR/SPV MONITORING

### **Dashboard Stok Ready:**

```
┌─────────────────────────────────────────┐
│  📦 STOK READY - All Toko               │
├─────────────────────────────────────────┤
│                                         │
│  🏪 Transmart MTC                       │
│  ┌─────────────────────────────────┐   │
│  │ Produk        │Ready│OTW │Status│   │
│  ├───────────────┼─────┼────┼──────┤   │
│  │ Y19s 8/128    │  5  │ 10 │  ✅  │   │
│  │ V40 12/256    │  2  │  0 │  ⚠️  │   │
│  │ Y400 6/128    │  0  │ 15 │  🚚  │   │
│  └─────────────────────────────────┘   │
│                                         │
│  🏪 Panakukkang                         │
│  ┌─────────────────────────────────┐   │
│  │ Y19s 8/128    │ 12  │  0 │  ✅  │   │
│  │ V40 12/256    │  8  │  5 │  ✅  │   │
│  │ Y400 6/128    │  1  │  0 │  ⚠️  │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ⚠️ CRITICAL ALERTS (3)                 │
│  - MTC: V40 tipis (only 2 unit)        │
│  - Panakukkang: Y400 hampir habis      │
│  - Mall Ratu: Y19s kosong              │
│                                         │
│  [📤 Generate Order Recommendation]     │
│  [📢 Send Alert to Discord]             │
│                                         │
└─────────────────────────────────────────┘
```

---

## ⚠️ MASALAH & RECOMMENDATIONS

### **Masalah di Sistem Lama:**

**1. Data Inconsistency:**
```
❌ Stok Gudang (aggregate) vs Stok Toko (per IMEI)
   tidak sinkron!

❌ Tidak ada reconciliation process

❌ Tidak ada stock movement tracking
   (sold, transferred, damaged, etc.)
```

**2. No Auto-Decrement:**
```
❌ Saat promotor input jualan dengan IMEI,
   stok tidak auto-berkurang!

❌ Manual adjustment needed (risky!)

❌ Potential overselling issue
```

**3. Duplicate Input:**
```
❌ Promotor input stok per IMEI
❌ SATOR input stok gudang per model

Kenapa perlu 2x input?
Should streamline!
```

**4. Multiple "Tipe" Confusing:**
```
❌ Display, Ready, Transit, Chip
   Terlalu banyak kategori

❌ Promotor sering bingung pilih yang mana

❌ Tidak ada clear transition rules
   (kapan Transit jadi Ready?)
```

---

### **Recommendations untuk Sistem Baru:**

#### **Option A: Simplified (Recommended)**

```
┌─────────────────────────────────────────┐
│  SINGLE SOURCE OF TRUTH: Gudang Pusat  │
├─────────────────────────────────────────┤
│                                         │
│  1. SATOR input stok gudang (daily)     │
│     → This is the master data           │
│                                         │
│  2. Promotor input penjualan            │
│     → Auto-decrement from gudang stock  │
│                                         │
│  3. Per-IMEI tracking (optional)        │
│     → Only for high-value items (>5jt)  │
│     → Or for warranty tracking          │
│                                         │
│  4. Display stock (separate counter)    │
│     → Not counted in sellable stock     │
│                                         │
└─────────────────────────────────────────┘
```

**Benefits:**
- ✅ No double input
- ✅ Auto-decrement on sale
- ✅ Always accurate
- ✅ Less confusion

#### **Option B: Full Tracking (Complex)**

```
Keep current system but add:
1. Stock movement log
2. Auto-reconciliation daily
3. Transfer tracking (toko → toko)
4. Damaged/return tracking
5. Real-time sync

Benefits: Complete audit trail
Drawbacks: Complex, overhead
```

---

## 🚀 UNTUK FLUTTER APP

### **Simplified Stock Module:**

**Promotor Features:**
```
1. Quick Stock In (Scan IMEI)
   - Default: Ready stock
   - Optional: Tentukan display/chip

2. No manual counting!
   - System auto-count dari IMEI scans

3. Visual stock status
   - My toko stock overview
   - Color coded: Green/Yellow/Red
```

**SATOR Features:**
```
1. Warehouse Stock Input
   - AI image upload (Gemini)
   - Manual table input
   - Bulk edit

2. Multi-Toko Monitoring
   - Dashboard all toko
   - Alert system
   - Drill-down per toko

3. Restock Recommendation
   - AI-based (sales velocity)
   - Manual adjust
   - One-tap send order
```

### **Data Sync Strategy:**

```
App (Offline) → Queue → Cloud (When online)

Queue Priority:
1. Sales (highest - must sync ASAP)
2. Stock In (high)
3. Stock adjustment (medium)

Conflict Resolution:
- Server wins (inventory)
- Show confirmation to user
```

---

## 📋 SUMMARY

### **3 Types of Stock:**

| Type | Who | What | Where Stored |
|------|-----|------|--------------|
| **Stok Toko** | Promotor | Per IMEI, individual units | `stok` table |
| **Stok Gudang** | SATOR | Per model, aggregate qty | `stok_gudang_harian` |
| **Stok Ready** | System | Computed, per toko | `stok_ready` table |

### **Key Workflows:**

1. **Morning:** Promotor scan stok masuk → SATOR input gudang
2. **During Day:** Auto-alerts kalau stok < minimal
3. **Evening:** Generate rekomendasi order
4. **Weekly:** Reconciliation & adjustment

### **Critical for Rebuild:**

✅ **Must Have:**
- Single source of truth
- Auto-decrement on sale
- AI image parsing
- Alert system

⚠️ **Nice to Have:**
- Per-IMEI tracking
- Stock movement log
- Transfer between toko
- Damage tracking

---

**NEXT:** Mau saya buatkan visual mockup untuk stock management di Flutter app?
