# 📦 PRODUCT MANAGEMENT SYSTEM - PLANNING
**Date:** 8 Januari 2026  
**Status:** Planning - In Progress  
**Purpose:** Master data produk VIVO untuk bonus, target, dan sell-in system

---

## 🎯 PURPOSE & SCOPE

### **Why Product Management?**
```
✅ Master data untuk semua sistem (bonus, target, sell-in)
✅ Harga SRP → Auto-determine bonus calculation
✅ Kategori → Tentukan Tipe Fokus atau tidak
✅ Dynamic → Admin bisa ubah tanpa coding
✅ Historical → Track perubahan harga/status
```

### **Connected Systems:**
```
Product Management
├─→ Bonus Calculation (range-based, flat cash, rasio)
├─→ Target System (Tipe Fokus designation)
├─→ Sell-In System (stock, ordering, margin)
├─→ Sales Reporting (kategori, performance)
└─→ SATOR Reward (eligible products per periode)
```

---

## 📊 DATA STRUCTURE

### **A. PRODUCT MASTER DATA**

#### **1. Product Information**
```
- Nama Produk: "Y400"
- Varian: "8/256" (RAM/Storage)
- Warna: "Black", "Purple", "Gold", etc.
- Series/Kategori: "Y-Series", "V-Series", "X-Series", "iQoo"

Kombinasi unik: Y400 8/256 Black (1 SKU)
```

#### **2. Pricing**
```
- Harga SRP (Harga Toko): Rp 3.500.000
  └─ Untuk: Bonus calculation, target omzet
  
- Harga Gudang (Modal): Rp 3.200.000
  └─ Untuk: Sell-in order, margin calculation
  
- Margin: Rp 300.000 (auto-calculated)
  └─ Formula: SRP - Harga Gudang
  └─ Display as: Rp 300.000 (8.6%)
```

#### **3. Classification**

**Tipe Fokus:**
```
✅ Produk ≥ Rp 2.000.000 = Tipe Fokus
❌ Produk < Rp 2.000.000 = Non-Fokus

Auto-determined berdasarkan Harga SRP
Admin bisa manual override (special case)
```

**Bonus Type:**
```
3 Jenis:
1. Range-Based (Default)
   └─ Harga SRP menentukan range bonus
   
2. Flat Cash (X Series)
   └─ Fixed bonus per produk
   └─ Ignore range-based calculation
   
3. Rasio 2:1 (Y02, Y03T, Y04S)
   └─ Qty dibagi 2 sebelum bonus calculation
```

**Target Eligibility:**
```
Tipe Fokus dengan Target Detail:
├─ Y400 ✅ (punya target detail)
├─ Y29 ✅ (punya target detail)
├─ V-Series ✅ (punya target detail)
├─ iQoo ❌ (masuk total fokus, tapi no detail target)
└─ X-Series ❌ (masuk total fokus, tapi no detail target)

Admin toggle: "Punya Target Detail" (boolean)
```

**SATOR Reward Eligible:**
```
Dynamic per periode (bulan):
- Januari 2026: Y400, Y29, V60 Lite
- Februari 2026: (Admin bisa ubah)

Admin control:
├─ Toggle eligible (per produk per bulan)
├─ Set skala unit (< 30, 30-50, > 50)
└─ Set reward amount per skala
```

#### **4. Status & Availability**
```
- Status: Active / Inactive
- Tanggal Mulai: 2025-12-01 (produk tersedia sejak)
- Tanggal Akhir: null (masih aktif) / 2026-03-31 (discontinue)
- Reason Inactive: "Discontinue", "Out of Stock", "Promo Ended"
```

---

## 🎨 ADMIN UI FEATURES

### **A. Product List (Main View)**

```
┌────────────────────────────────────────────────────────────────┐
│ 📦 PRODUCT MANAGEMENT                    [+ Tambah Produk]     │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Filter: [Series ▼] [Tipe Fokus ▼] [Status ▼]  🔍 Search        │
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Y400 8/256                                      Active ✅ │  │
│ │ ├─ Warna: Black, Purple, Gold                            │  │
│ │ ├─ SRP: Rp 3.500.000 | Gudang: Rp 3.200.000              │  │
│ │ ├─ Margin: Rp 300.000 (8.6%)                             │  │
│ │ ├─ Series: Y-Series | Tipe Fokus ✅                      │  │
│ │ ├─ Bonus Type: Range-Based (Rp 3-4jt → Rp 45k)          │  │
│ │ ├─ Target Detail: Ya ✅                                   │  │
│ │ └─ Reward Eligible: Jan 2026 ✅                          │  │
│ │                                      [Edit] [History] ⋮  │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ X300 8/256                                      Active ✅ │  │
│ │ ├─ Warna: Black, Gold                                    │  │
│ │ ├─ SRP: Rp 8.000.000 | Gudang: Rp 7.500.000              │  │
│ │ ├─ Margin: Rp 500.000 (6.3%)                             │  │
│ │ ├─ Series: X-Series | Tipe Fokus ✅                      │  │
│ │ ├─ Bonus Type: Flat Cash (Rp 250.000/unit)              │  │
│ │ ├─ Target Detail: Tidak ❌                                │  │
│ │ └─ Reward Eligible: - (not eligible)                     │  │
│ │                                      [Edit] [History] ⋮  │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Y02 4/64                                        Active ✅ │  │
│ │ ├─ Warna: Black, Blue                                    │  │
│ │ ├─ SRP: Rp 1.200.000 | Gudang: Rp 1.100.000              │  │
│ │ ├─ Margin: Rp 100.000 (8.3%)                             │  │
│ │ ├─ Series: Y-Series | Tipe Fokus ❌ (< 2jt)              │  │
│ │ ├─ Bonus Type: Rasio 2:1 (Official Rp 5k)               │  │
│ │ ├─ Target Detail: Tidak ❌                                │  │
│ │ └─ Reward Eligible: - (not eligible)                     │  │
│ │                                      [Edit] [History] ⋮  │  │
│ └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

---

### **B. Add/Edit Product Form**

```
┌────────────────────────────────────────────────────────────────┐
│ ✏️ EDIT PRODUK: Y400 8/256                                     │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│ INFORMASI DASAR                                                │
│ ├─ Nama Produk: [Y400____________]                             │
│ ├─ Varian: [8/256_____]                                        │
│ ├─ Warna: [Black, Purple, Gold________] (comma separated)     │
│ └─ Series: [Y-Series ▼]                                        │
│                                                                 │
│ HARGA                                                           │
│ ├─ Harga SRP (Toko): [Rp 3.500.000_____]                      │
│ ├─ Harga Gudang (Modal): [Rp 3.200.000_____]                  │
│ └─ Margin: Rp 300.000 (8.6%) [Auto-calculated]                │
│                                                                 │
│ KLASIFIKASI                                                     │
│ ├─ Tipe Fokus: [✅] Auto (≥ Rp 2jt)  [ ] Manual Override       │
│ │              Result: ✅ Tipe Fokus                           │
│ │                                                               │
│ ├─ Bonus Type:                                                 │
│ │  ( ) Range-Based (Default)                                  │
│ │  ( ) Flat Cash → Amount: [Rp 250.000___]                    │
│ │  ( ) Rasio 2:1 → Bonus: Official [Rp 5.000] Training [Rp 4.000] │
│ │                                                               │
│ ├─ Punya Target Detail: [✅] Ya  [ ] Tidak                     │
│ │  (untuk Tipe Fokus, tentukan ada target per produk atau tidak) │
│ │                                                               │
│ └─ SATOR Reward Eligible:                                      │
│    ├─ Periode: [Januari 2026 ▼]  [✅] Eligible                 │
│    ├─ Skala Unit:                                              │
│    │  < [30__] unit → Reward: [Rp 500.000___]                 │
│    │  [30__] - [50__] unit → Reward: [Rp 750.000___]          │
│    │  > [50__] unit → Reward: [Rp 1.250.000___]               │
│    └─ Denda < 80%: [Rp 100.000___]                            │
│                                                                 │
│ STATUS                                                          │
│ ├─ Status: [✅] Active  [ ] Inactive                           │
│ ├─ Tanggal Mulai: [2025-12-01_____]                           │
│ └─ Tanggal Akhir: [_________] (kosong = masih aktif)          │
│                                                                 │
│                             [Simpan] [Batal]                   │
└────────────────────────────────────────────────────────────────┘
```

---

### **C. Bulk Operations**

```
┌────────────────────────────────────────────────────────────────┐
│ 📋 BULK OPERATIONS                                             │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 1. BULK UPDATE HARGA                                           │
│    ├─ Upload Excel: [Choose File] [Template Download]         │
│    ├─ Columns: Nama Produk, Varian, SRP Baru, Gudang Baru     │
│    └─ Auto-update margin calculation                           │
│                                                                 │
│ 2. BULK TOGGLE STATUS                                          │
│    ├─ Series: [Y-Series ▼]                                     │
│    ├─ Action: [Set Active ▼] / [Set Inactive ▼]               │
│    └─ Reason: [Discontinue ▼]                                  │
│                                                                 │
│ 3. BULK SET REWARD (Per Periode)                               │
│    ├─ Periode: [Januari 2026 ▼]                                │
│    ├─ Produk: [Select Multiple ▼]                              │
│    │  ☑ Y400, ☑ Y29, ☑ V60 Lite                                │
│    └─ Copy Settings From: [Desember 2025 ▼]                    │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

---

## 🔗 INTEGRATION WITH OTHER SYSTEMS

### **A. Bonus Calculation**

**Auto-Linking:**
```javascript
// Promotor jual produk
sales_record = {
  product_id: 123, // Y400 8/256 Black
  qty: 3
}

// System auto-fetch product data
product = Product.get(123)
harga_srp = product.harga_srp // Rp 3.500.000

// Determine bonus type
if (product.bonus_type === 'flat_cash') {
  bonus = product.flat_cash_amount * qty
} else if (product.bonus_type === 'ratio') {
  bonus_qty = floor(qty / product.ratio_divider)
  bonus = bonus_qty * product.ratio_bonus_official
} else {
  // Range-based
  bonus_range = BonusRange.find_by_price(harga_srp, promotor.status)
  bonus = bonus_range.amount * qty
}
```

**Impact Harga Berubah:**
```
Admin ubah harga SRP Y400: Rp 3.500.000 → Rp 4.100.000

Auto-update:
├─ Bonus range: Rp 3-4jt (Rp 45k) → Rp 4-5jt (Rp 60k) ✅
├─ Tipe Fokus: Ya → Ya (masih ≥ 2jt) ✅
└─ Margin: Recalculated ✅

Historical data (sales lama):
└─ Tetap pakai harga lama (snapshot saat transaksi) ✅
```

---

### **B. Target System**

**Tipe Fokus Auto-Detection:**
```
Target Tipe Fokus (Unit):
├─ Ambil semua produk dengan is_tipe_fokus = true
│  (auto-determined: harga_srp >= 2.000.000)
│  
└─ Sales Y400 (Rp 3.5jt) → Count ✅
   Sales Y02 (Rp 1.2jt) → Skip ❌
```

**Target Detail per Produk:**
```
Target Detail:
├─ Hanya produk dengan has_detail_target = true
│  
└─ Y400: Target 50 unit ✅
   iQoo: No target (tapi masuk total fokus) ✅
```

---

### **C. Sell-In System**

**Stock & Ordering:**
```
Rekomendasi Order:
├─ Ambil data: harga_gudang (untuk calculate modal toko)
├─ Margin visibility (toko lihat profit potential)
└─ Filter: is_active = true (jangan recommend inactive products)

Order Processing:
├─ Harga Gudang × Qty = Total Modal
└─ Harga SRP × Qty = Projected Revenue
```

---

### **D. SATOR Reward**

**Dynamic Reward Products:**
```
Admin set reward untuk Januari 2026:
├─ Y400: Eligible ✅
│  ├─ < 30 unit: Rp 500k
│  ├─ 30-50 unit: Rp 750k
│  └─ > 50 unit: Rp 1.25jt
│  
├─ Y29: Eligible ✅
└─ V60 Lite: Eligible ✅

Februari 2026:
└─ Admin bisa ubah produk/skala/amount
```

---

## 💾 DATABASE SCHEMA (Draft)

### **Table: products**
```sql
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  
  -- Basic Info
  nama_produk VARCHAR(100) NOT NULL, -- "Y400" or "Demo V60"
  varian VARCHAR(50), -- "8/256"
  warna VARCHAR(50) NOT NULL, -- "Black", "Purple", "Green" (single color per SKU)
  series VARCHAR(50) NOT NULL, -- "Y-Series", "V-Series", "X-Series", "iQoo"
  
  -- Pricing
  harga_srp DECIMAL(12,2), -- Rp 3.500.000 (NULL for demo products)
  harga_gudang DECIMAL(12,2) NOT NULL, -- Rp 3.200.000 (always has modal)
  margin DECIMAL(12,2) GENERATED ALWAYS AS (
    CASE WHEN harga_srp IS NOT NULL 
    THEN harga_srp - harga_gudang 
    ELSE NULL END
  ) STORED,
  margin_pct DECIMAL(5,2) GENERATED ALWAYS AS (
    CASE WHEN harga_srp IS NOT NULL AND harga_gudang > 0
    THEN ((harga_srp - harga_gudang) / harga_gudang * 100)
    ELSE NULL END
  ) STORED,
  
  -- Product Type
  is_demo BOOLEAN DEFAULT false, -- TRUE for demo products
  
  -- Classification (only for non-demo)
  is_tipe_fokus BOOLEAN GENERATED ALWAYS AS (
    CASE WHEN is_demo = false AND harga_srp >= 2000000 
    THEN true 
    ELSE false END
  ) STORED,
  tipe_fokus_override BOOLEAN DEFAULT NULL, -- Manual override
  has_detail_target BOOLEAN DEFAULT true,
  
  -- Bonus Type (skip if is_demo = true)
  bonus_type VARCHAR(20) DEFAULT 'range', -- 'range', 'flat_cash', 'ratio', 'none'
  flat_cash_amount DECIMAL(10,2), -- For X-Series
  ratio_divider DECIMAL(3,1) DEFAULT 1.0, -- For Y02 (2.0 = 2:1)
  ratio_bonus_official DECIMAL(10,2),
  ratio_bonus_training DECIMAL(10,2),
  
  -- Status
  is_active BOOLEAN DEFAULT true,
  tanggal_mulai DATE NOT NULL DEFAULT CURRENT_DATE,
  tanggal_akhir DATE,
  inactive_reason VARCHAR(100),
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id),
  updated_by INTEGER REFERENCES users(id),
  
  -- Constraints
  CONSTRAINT check_demo_pricing CHECK (
    (is_demo = false AND harga_srp IS NOT NULL) OR
    (is_demo = true AND harga_srp IS NULL)
  ),
  CONSTRAINT check_demo_bonus CHECK (
    (is_demo = false) OR
    (is_demo = true AND bonus_type = 'none')
  )
);

-- Unique constraint per SKU
CREATE UNIQUE INDEX idx_product_sku_unique ON products(nama_produk, varian, warna) 
WHERE is_active = true;

-- Indexes
CREATE INDEX idx_products_series ON products(series);
CREATE INDEX idx_products_tipe_fokus ON products(is_tipe_fokus) WHERE is_active = true;
CREATE INDEX idx_products_active ON products(is_active);
CREATE INDEX idx_products_demo ON products(is_demo);
CREATE INDEX idx_products_sellable ON products(is_active, is_demo) 
WHERE is_active = true AND is_demo = false; -- For sell-out list
```

---

### **Table: product_reward_settings**
```sql
CREATE TABLE product_reward_settings (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id),
  periode VARCHAR(7) NOT NULL, -- "2026-01"
  
  is_eligible BOOLEAN DEFAULT false,
  
  -- Skala unit & reward
  scale_min_1 INTEGER, -- < 30
  reward_amount_1 DECIMAL(10,2),
  
  scale_min_2 INTEGER, -- 30
  scale_max_2 INTEGER, -- 50
  reward_amount_2 DECIMAL(10,2),
  
  scale_min_3 INTEGER, -- > 50
  reward_amount_3 DECIMAL(10,2),
  
  denda_amount DECIMAL(10,2) DEFAULT 100000, -- Denda < 80%
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id),
  
  UNIQUE(product_id, periode)
);
```

---

### **Table: product_price_history**
```sql
CREATE TABLE product_price_history (
  id SERIAL PRIMARY KEY,
  product_id INTEGER REFERENCES products(id),
  
  old_harga_srp DECIMAL(12,2),
  new_harga_srp DECIMAL(12,2),
  
  old_harga_gudang DECIMAL(12,2),
  new_harga_gudang DECIMAL(12,2),
  
  changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  changed_by INTEGER REFERENCES users(id),
  reason TEXT
);
```

---

## 🎯 BUSINESS RULES

### **1. Harga SRP (Critical!)**
```
✅ WAJIB ada (NOT NULL)
✅ Menentukan bonus calculation (range-based)
✅ Menentukan Tipe Fokus (≥ 2jt)
✅ Perubahan harga → History tracked
✅ Sales lama pakai harga snapshot (waktu transaksi)
```

### **2. Tipe Fokus**
```
Auto-Determined:
└─ harga_srp >= Rp 2.000.000 → Tipe Fokus ✅

Manual Override (Special Case):
└─ Admin bisa force true/false
└─ Example: Produk promo Rp 1.9jt tapi tetap dianggap fokus
```

### **3. Bonus Type Priority**
```
1. Cek: bonus_type = 'flat_cash' → Pakai flat_cash_amount
2. Cek: bonus_type = 'ratio' → Apply ratio, lalu pakai ratio_bonus
3. Default: bonus_type = 'range' → Query bonus_ranges table
```

### **4. Warna (Array)**
```
Produk bisa punya multiple warna:
└─ Y400 8/256: ["Black", "Purple", "Gold"]

Sell-In/Stock:
└─ SATOR harus specify warna exact
   (Y400 8/256 Black, bukan cuma Y400)
```

### **5. Product Lifecycle**
```
Active Product:
├─ is_active = true
├─ tanggal_akhir = null
└─ Tampil di semua dropdown/list

Inactive Product:
├─ is_active = false
├─ tanggal_akhir = filled
├─ inactive_reason = "Discontinue" / "Out of Stock" / etc
└─ TIDAK tampil di dropdown, tapi historical data tetap ada
```

### **6. Demo Products (Special Handling)**
```
Rules:
├─ is_demo = true
├─ harga_srp = NULL (tidak dijual ke konsumen)
├─ harga_gudang = Ada (modal dari gudang)
├─ bonus_type = 'none' (auto-set)
├─ is_tipe_fokus = false (auto-set)
├─ has_detail_target = false

Sell-In:
├─ Toko BISA order demo products ✅
├─ SATOR approve seperti produk biasa
├─ Gudang kirim ke toko
└─ Purpose: Display unit untuk toko

Sell-Out:
├─ Promotor TIDAK bisa input penjualan demo ❌
├─ Demo unit = display only
└─ Bonus calculation = skip

Stock Tracking:
├─ Track IMEI demo units ✅
├─ Status: "Display" (bukan "Fresh")
└─ Monitor keberadaan di toko

Filter Queries:
├─ Sell-Out Input: WHERE is_demo = false
├─ Sell-In Order: (no filter, include demo)
├─ Bonus Calculation: WHERE is_demo = false
└─ Target Achievement: WHERE is_demo = false
```

---

## 🚀 ADMIN WORKFLOWS

### **Workflow 1: Tambah Produk Baru**
```
1. Admin klik "Tambah Produk"
2. Isi form:
   ├─ Nama: Y500
   ├─ Varian: 12/512
   ├─ Warna: Black, Gold
   ├─ Series: Y-Series
   ├─ SRP: Rp 4.200.000
   ├─ Gudang: Rp 3.800.000
   ├─ Bonus Type: Range-Based (default)
   ├─ Target Detail: Ya
   └─ Reward: (skip dulu, set nanti)
3. Save
4. System auto-calculate:
   ├─ Margin: Rp 400k (10.5%)
   ├─ Tipe Fokus: Ya (≥ 2jt)
   └─ Bonus range: Rp 4-5jt → Rp 60k
5. Product tersedia di semua sistem ✅
```

---

### **Workflow 2: Update Harga Produk**
```
1. Admin pilih produk: Y400 8/256
2. Klik Edit
3. Ubah SRP: Rp 3.500.000 → Rp 4.100.000
4. Ubah Gudang: Rp 3.200.000 → Rp 3.700.000
5. System confirm:
   ⚠️ "Perubahan harga akan mempengaruhi:
      - Bonus calculation (Rp 45k → Rp 60k)
      - Margin (Rp 300k → Rp 400k)
      - Historical sales TIDAK berubah
      Lanjutkan?"
6. Admin confirm → Save
7. System log history:
   ├─ Old: SRP 3.5jt, Gudang 3.2jt
   ├─ New: SRP 4.1jt, Gudang 3.7jt
   ├─ Changed by: Admin X
   └─ Timestamp: 2026-01-08 14:30
```

---

### **Workflow 3: Set Reward Khusus (Bulanan)**
```
1. Admin klik "Reward Settings"
2. Pilih periode: Februari 2026
3. Copy from: Januari 2026 (optional)
4. Pilih produk eligible:
   ☑ Y400
   ☑ Y29
   ☐ V60 Lite (toggle off untuk Feb)
   ☑ Y500 (produk baru, tambahkan)
5. Set skala per produk:
   Y400:
   ├─ < 30 unit: Rp 500k
   ├─ 30-50: Rp 750k
   └─ > 50: Rp 1.25jt
6. Save
7. SATOR dashboard update:
   └─ Feb 2026 reward products: Y400, Y29, Y500 ✅
```

---

## ❓ CRITICAL QUESTIONS

### **1. SKU Level** ✅ CONFIRMED
**Decision:** Separate SKU per warna (Option A)
```
Y400 8/256 Purple = SKU 001
Y400 8/256 Green = SKU 002

Reason:
- Setiap warna = separate stock item
- IMEI tracking per warna
- Sell-in order must specify exact warna
- Harga sama, tapi stock & sales tracking terpisah
```

---

### **2. Harga Per Warna** ✅ CONFIRMED
**Decision:** Same price untuk semua warna (1 tipe produk = 1 harga set)
```
Y400 8/256:
├─ Purple: Harga Modal Rp 3.170.000, Harga Jual Rp 3.499.000
└─ Green:  Harga Modal Rp 3.170.000, Harga Jual Rp 3.499.000

Note: Kalau ada special edition beda harga, itu jadi produk baru
```

---

### **3. Series/Kategori** ✅ CONFIRMED
**Decision:** Berdasarkan data real (Januari 2026)
```
Series List:
├─ Y-Series (Y04S, Y400, Y19s PRO, Y21D)
├─ V-Series (V60, V60 Lite, V50, V50 Lite)
├─ X-Series (X300, X300 PRO)
└─ iQoo (iQoo 15 LG)

Admin bisa tambah series baru kalau ada produk baru
```

---

### **4. Bonus Range Table** ✅ CONFIRMED
**Decision:** DYNAMIC - Admin bisa ubah kapan saja

**Bonus Range Settings (Admin Control):**
```
Table: bonus_ranges

Current (Januari 2026):
< Rp 2.000.000       → Official Rp 10k,  Training Rp 7k
Rp 2.000.000 - 2.999 → Official Rp 25k,  Training Rp 20k
Rp 3.000.000 - 3.999 → Official Rp 45k,  Training Rp 40k
Rp 4.000.000 - 4.999 → Official Rp 60k,  Training Rp 50k
Rp 5.000.000 - 5.999 → Official Rp 80k,  Training Rp 60k
> Rp 6.000.000        → Official Rp 110k, Training Rp 90k

Admin UI:
├─ Add new range
├─ Edit amount per range
├─ Delete range
├─ Set effective date (periode berlaku)
└─ History tracking (perubahan dicatat)
```

---

### **5. Demo Products** ✅ CONFIRMED
**Decision:** Masuk sistem dengan special handling
```
Demo Products Characteristics:
├─ Masuk sistem ✅ (complete product record)
├─ Harga Modal: Ada (dari gudang)
├─ Harga Jual: NULL/0 (tidak dijual ke konsumen)
├─ Flag: is_demo = true
├─ Sell-In: BISA diorder toko ✅
│  └─ Toko order demo unit untuk display
├─ Bonus Calculation: SKIP ❌
│  └─ Promotor tidak dapat bonus untuk demo
├─ Stock Tracking: YA ✅
│  └─ Track IMEI demo units
└─ Target: Tidak masuk perhitungan ✅

Use Cases:
1. Toko order "Demo V60 8/256 Gray" via Sell-In
2. SATOR approve, gudang kirim
3. Promotor terima stock demo
4. Display di toko (TIDAK dijual)
5. No bonus untuk promotor
```

---

---

## 💾 BONUS RANGES TABLE (DYNAMIC ADMIN CONTROL)

### **Table: bonus_ranges**
```sql
CREATE TABLE bonus_ranges (
  id SERIAL PRIMARY KEY,
  
  -- Range
  price_min DECIMAL(12,2) NOT NULL,
  price_max DECIMAL(12,2), -- NULL = no upper limit
  
  -- Bonus amounts
  bonus_official DECIMAL(10,2) NOT NULL,
  bonus_training DECIMAL(10,2) NOT NULL,
  
  -- Periode
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_until DATE, -- NULL = active indefinitely
  
  -- Metadata
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_by INTEGER REFERENCES users(id),
  
  -- Constraint: no overlapping ranges for same periode
  CONSTRAINT check_price_range CHECK (price_max IS NULL OR price_max > price_min)
);

-- Seed data (current rules)
INSERT INTO bonus_ranges (price_min, price_max, bonus_official, bonus_training) VALUES
  (0, 1999999, 10000, 7000),
  (2000000, 2999999, 25000, 20000),
  (3000000, 3999999, 45000, 40000),
  (4000000, 4999999, 60000, 50000),
  (5000000, 5999999, 80000, 60000),
  (6000000, NULL, 110000, 90000); -- NULL = > 6jt
```

### **Admin UI: Bonus Range Settings**
```
┌────────────────────────────────────────────────────────────────┐
│ 💰 BONUS RANGE SETTINGS                  [+ Tambah Range]     │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Range: Rp 0 - Rp 1.999.999                               │  │
│ │ ├─ Bonus Official:  [Rp 10.000___]                       │  │
│ │ ├─ Bonus Training:  [Rp 7.000___]                        │  │
│ │ ├─ Effective From: [2025-01-01] Until: [________] (aktif)│  │
│ │ └─ Status: Active ✅                [Edit] [Delete] ⋮    │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Range: Rp 2.000.000 - Rp 2.999.999                       │  │
│ │ ├─ Bonus Official:  [Rp 25.000___]                       │  │
│ │ ├─ Bonus Training:  [Rp 20.000___]                       │  │
│ │ └─ Status: Active ✅                [Edit] [Delete] ⋮    │  │
│ └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│ ... (ranges 3-4jt, 4-5jt, 5-6jt)                               │
│                                                                 │
│ ┌──────────────────────────────────────────────────────────┐  │
│ │ Range: > Rp 6.000.000 (No Upper Limit)                  │  │
│ │ ├─ Bonus Official:  [Rp 110.000___]                      │  │
│ │ ├─ Bonus Training:  [Rp 90.000___]                       │  │
│ │ └─ Status: Active ✅                [Edit] [Delete] ⋮    │  │
│ └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

---

## 📊 REAL PRODUCT DATA (Sample from January 2026)

### **Product Examples:**
```
1. Y04S 4/128 (2 SKUs)
   ├─ Purple: Modal Rp 1.660.000, Jual Rp 1.799.000, Margin Rp 139k (8.4%)
   └─ Green:  Modal Rp 1.660.000, Jual Rp 1.799.000, Margin Rp 139k (8.4%)
   Series: Y-Series
   Tipe Fokus: ❌ (< 2jt)
   Bonus: Range-based (< 2jt → Official Rp 10k, Training Rp 7k)

2. Y400 8/256 (2 SKUs)
   ├─ Purple: Modal Rp 3.170.000, Jual Rp 3.499.000, Margin Rp 329k (10.4%)
   └─ Green:  Modal Rp 3.170.000, Jual Rp 3.499.000, Margin Rp 329k (10.4%)
   Series: Y-Series
   Tipe Fokus: ✅ (≥ 2jt)
   Bonus: Range-based (3-4jt → Official Rp 45k, Training Rp 40k)
   Target Detail: ✅ Ya
   Reward Eligible: ✅ (Jan 2026)

3. X300 12/256 (3 SKUs)
   ├─ Pink:  Modal Rp 13.500.000, Jual Rp 14.999.000, Margin Rp 1.499k (11.1%)
   ├─ Blue:  Modal Rp 13.500.000, Jual Rp 14.999.000, Margin Rp 1.499k (11.1%)
   └─ Black: Modal Rp 13.500.000, Jual Rp 14.999.000, Margin Rp 1.499k (11.1%)
   Series: X-Series
   Tipe Fokus: ✅ (≥ 2jt)
   Bonus: Flat Cash (Rp 250.000/unit) - NOT range-based
   Target Detail: ❌ Tidak
   Reward Eligible: ❌

4. V60 Lite 5G 8/256 (3 SKUs)
   ├─ Blue:  Modal Rp 4.500.000, Jual Rp 4.999.000, Margin Rp 499k (11.1%)
   ├─ Black: Modal Rp 4.500.000, Jual Rp 4.999.000, Margin Rp 499k (11.1%)
   └─ Pink:  Modal Rp 4.500.000, Jual Rp 4.999.000, Margin Rp 499k (11.1%)
   Series: V-Series
   Tipe Fokus: ✅ (≥ 2jt)
   Bonus: Range-based (4-5jt → Official Rp 60k, Training Rp 50k)
   Target Detail: ✅ Ya
   Reward Eligible: ✅ (Jan 2026 - V60 Lite Series)

5. Demo V60 8/256 (3 SKUs)
   ├─ Gray:   Modal Rp 4.200.000, Jual: - (Demo unit)
   ├─ Purple: Modal Rp 4.200.000, Jual: - (Demo unit)
   └─ Blue:   Modal Rp 4.200.000, Jual: - (Demo unit)
   Series: V-Series
   Tipe Fokus: N/A (Demo)
   Bonus: ❌ No bonus (demo unit)
   is_demo: ✅ true
```

**Total Products (from Excel):** ~75 SKUs (25 tipe × ~3 warna rata-rata)

---

## 📋 NEXT STEPS

1. ✅ **SKU per warna - CONFIRMED**
2. ✅ **Harga sama per warna - CONFIRMED**
3. ✅ **Series list - CONFIRMED** (Y, V, X, iQoo)
4. ✅ **Bonus range dynamic - CONFIRMED**
5. ✅ **Demo products handling - CONFIRMED**
   - Masuk sistem, orderable via Sell-In
   - No bonus calculation
   - Special `is_demo` flag

---

## ✅ PLANNING COMPLETE - READY FOR NEXT PHASE

**Product Management System:** 100% Planned ✅

**What's Locked:**
- Data structure (SKU per warna)
- Pricing model (SRP + Gudang + Margin)
- Classification (Tipe Fokus, Series, Bonus Type)
- Demo products handling
- Bonus ranges (dynamic admin control)
- Integration points (Bonus, Target, Sell-In)

**Next Planning Topics:**
1. **Permission & Access** - Siapa bisa manage produk?
2. **Reporting Structure** - Dashboard & export
3. **Database Schema Finalization** - Complete ERD
4. **API Specs** - Endpoints & integration

---

**Status:** Product Management Planning 100% LOCKED ✅
