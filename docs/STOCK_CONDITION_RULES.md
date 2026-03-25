# 📦 STOCK CONDITION RULES - FINAL SPECIFICATION
**Date:** 8 Januari 2026  
**Status:** 100% LOCKED ✅  
**Purpose:** Define rules untuk kondisi stok: Fresh, Chip, Display

---

## 🎯 OVERVIEW: 3 KONDISI STOK

### **Summary:**
```
STOCK CONDITION (tipe_stok):
├─ 1. Fresh (Ready) - Produk baru, sealed box
├─ 2. Chip - IMEI sudah aktivasi (bonus sudah dibayar)
└─ 3. Display - Demo unit untuk display

HARGA: SAMA untuk semua kondisi (dari master product)
Tidak ada discount khusus untuk chip/display.
Discount hanya jika ada promo cashback/refund.
```

### **Cuci Gudang = PRODUCT CLASSIFICATION (bukan stock condition):**
```
Cuci Gudang = Produk model LAMA yang ada penggantinya

Contoh:
├─ Y19: is_cuci_gudang = true (model lama, ada Y19s)
└─ Y19s: is_cuci_gudang = false (model baru/current)

Ini di-set di MASTER PRODUCT, bukan di stock.
```

---

## 📋 KONDISI 1: FRESH (READY)

### **Definition:**
```
Produk baru, sealed box, kondisi sempurna
= Stok normal untuk dijual
```

### **Rules:**
```
✅ Harga: SRP normal (dari master product)
✅ Bonus: Dibayar SAAT SOLD (normal calculation)
✅ Target: Masuk perhitungan omzet & unit
✅ IMEI: Wajib di-track
✅ Stock: Ada sampai SOLD atau di-CHIP
```

### **Flow:**
```
Fresh Stock:
├─→ SOLD (Normal Sale)
│   └─ Bonus dibayar saat ini ✅
│   └─ Stock HILANG (marked as sold)
│
└─→ CHIP Activation
    └─ Bonus dibayar saat ini ✅
    └─ Stock TETAP ADA (status: chip)
    └─ Perlu approval atasan
```

---

## 📋 KONDISI 2: CHIP

### **Definition:**
```
Produk yang IMEI-nya sudah diaktivasi
= Bonus SUDAH DIBAYAR saat aktivasi chip
= Masih bisa dijual, tapi no additional bonus
```

### **Rules:**
```
✅ Harga: SRP normal (SAMA dengan fresh!)
✅ Bonus: SUDAH DIBAYAR saat chip activation
✅ Target: Masuk perhitungan (saat chip activation)
✅ IMEI: Same record, status berubah
✅ Stock: Tetap ada sampai SOLD
```

### **CRITICAL: 1 IMEI = 1 BONUS**
```
❌ TIDAK BOLEH double bonus!

Timeline:
1. Fresh masuk → Bonus: Rp 0 (belum dijual)
2. Fresh → Chip → Bonus: Rp 45.000 (dibayar!)
3. Chip → Sold → Bonus: Rp 0 (sudah dibayar!)

Total bonus per IMEI: Rp 45.000 (sekali saja)
```

### **Chip Activation Requirements:**
```
1. Approval atasan (SATOR/SPV)
2. Tujuan chip harus jelas:
   ├─ Customer mau lihat isi box
   ├─ Customer test dulu sebelum beli
   ├─ Promo tertentu (dengan approval)
   └─ [Alasan lain yang valid]
3. Scan IMEI untuk aktivasi
4. Record: siapa, kapan, alasan
```

### **Flow:**
```
Chip Stock:
└─→ SOLD
    └─ Bonus: Rp 0 (sudah dibayar saat chip!)
    └─ Stock HILANG (marked as sold)
    └─ Omzet: Masuk (tapi bonus sudah dihitung sebelumnya)
```

---

## 📋 KONDISI 3: DISPLAY

### **Definition:**
```
Demo unit untuk dipajang di toko
= Untuk customer lihat/coba, BUKAN untuk dijual
```

### **Rules:**
```
✅ Harga: Sama dengan SRP (untuk asset tracking)
✅ Bonus: TIDAK ADA (display = not for sale)
✅ Target: TIDAK masuk perhitungan
✅ IMEI: Di-track (asset management)
✅ Stock: Tetap ada (long-term)
```

### **Sources of Display:**
```
1. Demo Products (is_demo = true di master product)
   └─ Order khusus untuk display
   └─ Never intended for sale

2. Regular Products dijadikan Display
   └─ Convert dari Fresh → Display
   └─ Rare case (usually use demo products)
```

### **Display → Chip (Special Case):**
```
Jika display unit mau dijual:
1. Convert: Display → Chip
2. Perlu approval atasan
3. Bonus: Dibayar saat konversi (reduced? TBD)
4. Then: Chip → Sold (no additional bonus)
```

---

## 💾 DATABASE SCHEMA

### **Table: stok**
```sql
CREATE TABLE stok (
  id SERIAL PRIMARY KEY,
  
  -- Product & Location
  produk_id INTEGER REFERENCES products(id),
  toko_id INTEGER REFERENCES toko(id),
  promotor_id INTEGER REFERENCES users(id),
  
  -- IMEI Tracking
  imei VARCHAR(255) UNIQUE NOT NULL,
  
  -- Stock Condition
  tipe_stok VARCHAR(20) NOT NULL, -- 'fresh', 'chip', 'display'
  
  -- Bonus Tracking (CRITICAL!)
  bonus_paid BOOLEAN DEFAULT false,
  bonus_amount DECIMAL(10,2),
  bonus_paid_at TIMESTAMP,
  
  -- Chip Details (if applicable)
  chip_reason TEXT, -- "Customer mau test", dll
  chip_approved_by INTEGER REFERENCES users(id),
  chip_approved_at TIMESTAMP,
  
  -- Status
  is_sold BOOLEAN DEFAULT false,
  sold_at TIMESTAMP,
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id),
  
  -- Constraints
  CONSTRAINT check_tipe_stok CHECK (tipe_stok IN ('fresh', 'chip', 'display'))
);

-- Indexes
CREATE INDEX idx_stok_toko ON stok(toko_id);
CREATE INDEX idx_stok_produk ON stok(produk_id);
CREATE INDEX idx_stok_tipe ON stok(tipe_stok);
CREATE INDEX idx_stok_imei ON stok(imei);
CREATE INDEX idx_stok_unsold ON stok(is_sold) WHERE is_sold = false;
```

---

## 🔄 STATUS TRANSITIONS

### **Allowed:**
```
Fresh → Chip (chip activation, bonus paid)
Fresh → Sold (normal sale, bonus paid)
Fresh → Display (rare, convert to demo)
Chip → Sold (sale, NO bonus)
Display → Chip (clearance, bonus paid - reduced?)
```

### **NOT Allowed:**
```
❌ Chip → Fresh (cannot "undo" chip)
❌ Display → Fresh (cannot sell as new)
❌ Sold → anything (terminal state)
```

---

## 🔀 STOCK TRANSFER SYSTEM (Antar Toko)

### **Overview:**
```
Tujuan: Track perpindahan stok antar toko dengan 100% akurasi
├─ Setiap IMEI harus tau lokasi pasti
├─ Transfer history tercatat lengkap
└─ Stock per toko selalu valid

2 Jenis Transfer:
1. Request Transfer (Promotor A minta ke Promotor B)
2. Direct Transfer (Barang pindah langsung, tanpa request)
```

---

### **TYPE 1: REQUEST TRANSFER**

#### **Flow:**
```
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Promotor A (Butuh Stok)                            │
│ ├─ Cari produk di sistem: "Y400 8/256 Purple"               │
│ ├─ Lihat stok toko lain yang punya                         │
│ │   ├─ Toko B (MTC): 5 unit ✅                              │
│ │   └─ Toko C (Lippo): 2 unit ✅                            │
│ └─ Pilih toko & qty: "Request 2 unit dari Toko B"          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Promotor B (Punya Stok) - NOTIFICATION             │
│ ├─ Dapat notifikasi: "Ahmad (Toko A) request 2 unit Y400"  │
│ ├─ Pilih IMEI yang mau di-transfer:                        │
│ │   ☑ IMEI: 123456 (Fresh)                                 │
│ │   ☑ IMEI: 123457 (Fresh)                                 │
│ └─ Action: [Approve] atau [Reject]                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: System Update (If Approved)                        │
│ ├─ IMEI 123456: toko_id = B → A                            │
│ ├─ IMEI 123457: toko_id = B → A                            │
│ ├─ Create transfer_log records                              │
│ └─ Notify Promotor A: "Transfer approved! 2 unit on the way"│
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Promotor A - Confirm Receive                        │
│ ├─ Barang fisik sampai                                      │
│ ├─ Scan IMEI untuk konfirmasi terima                        │
│ │   ✅ IMEI 123456 - Confirmed                              │
│ │   ✅ IMEI 123457 - Confirmed                              │
│ └─ Transfer status: COMPLETED                               │
└─────────────────────────────────────────────────────────────┘
```

#### **Request Statuses:**
```
1. PENDING   - Menunggu approval dari Promotor B
2. APPROVED  - Sudah di-approve, menunggu terima
3. REJECTED  - Ditolak oleh Promotor B
4. RECEIVED  - Barang sudah diterima & scan
5. CANCELLED - Dibatalkan oleh Promotor A
```

---

### **TYPE 2: DIRECT TRANSFER**

#### **Flow:**
```
┌─────────────────────────────────────────────────────────────┐
│ Promotor B (Transfer Out)                                   │
│ ├─ Pilih: "Transfer Langsung"                               │
│ ├─ Pilih Toko Tujuan: [Toko A ▼]                           │
│ ├─ Pilih IMEI:                                              │
│ │   ☑ IMEI: 123456 (Y400 Fresh)                            │
│ │   ☑ IMEI: 123457 (Y400 Fresh)                            │
│ ├─ Alasan (optional): "Rebalancing stok"                   │
│ └─ [Submit Transfer]                                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ System Update + Notification                                │
│ ├─ IMEI records updated (toko_id = B → A)                  │
│ ├─ Transfer log created                                     │
│ ├─ Notify Promotor A: "2 unit transferred from Toko B"     │
│ └─ Status: TRANSFERRED (auto-complete, no confirm needed)  │
└─────────────────────────────────────────────────────────────┘
```

**Note:** Direct transfer = trust-based. Promotor B langsung kirim tanpa request. Promotor A cukup terima barang fisik.

---

### **BONUS RULES (Transfer)**

```
RULE: Bonus untuk yang SCAN IMEI (jual/chip)
└─ Tidak perduli barang asal dari toko mana

Example:
├─ IMEI 123456 awalnya di Toko B (Promotor B)
├─ Transfer ke Toko A
├─ Promotor A scan untuk Chip → Bonus A dapat ✅
├─ Promotor A scan untuk Sold → Bonus A dapat ✅
└─ Promotor B: Bonus = Rp 0 (tidak scan untuk jual/chip)

❌ TIDAK ADA split bonus
❌ TIDAK ADA "bonus asal toko"
```

---

### **DATABASE SCHEMA: Transfer**

```sql
-- Transfer Requests (Type 1)
CREATE TABLE stock_transfer_requests (
  id SERIAL PRIMARY KEY,
  
  -- Request Details
  request_type VARCHAR(20) DEFAULT 'request', -- 'request' or 'direct'
  status VARCHAR(20) DEFAULT 'pending', -- pending/approved/rejected/received/cancelled
  
  -- Parties
  from_toko_id INTEGER REFERENCES toko(id),
  to_toko_id INTEGER REFERENCES toko(id),
  requested_by INTEGER REFERENCES users(id), -- Promotor A
  approved_by INTEGER REFERENCES users(id),  -- Promotor B (null if rejected)
  
  -- Product
  produk_id INTEGER REFERENCES products(id),
  qty_requested INTEGER,
  qty_approved INTEGER, -- Might be less than requested
  
  -- Reason
  reason TEXT,
  reject_reason TEXT,
  
  -- Timestamps
  requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  approved_at TIMESTAMP,
  received_at TIMESTAMP,
  
  CONSTRAINT check_different_toko CHECK (from_toko_id != to_toko_id)
);

-- Transfer Items (IMEI Level)
CREATE TABLE stock_transfer_items (
  id SERIAL PRIMARY KEY,
  transfer_request_id INTEGER REFERENCES stock_transfer_requests(id),
  
  -- IMEI
  stok_id INTEGER REFERENCES stok(id), -- Link to stok record
  imei VARCHAR(255) NOT NULL,
  
  -- Status
  is_received BOOLEAN DEFAULT false,
  received_at TIMESTAMP,
  
  -- Note
  condition_note TEXT -- "Barang OK", "Dus penyok", etc
);

-- Transfer History Log (All movements)
CREATE TABLE stock_movement_log (
  id SERIAL PRIMARY KEY,
  
  -- IMEI
  stok_id INTEGER REFERENCES stok(id),
  imei VARCHAR(255) NOT NULL,
  
  -- Movement
  from_toko_id INTEGER REFERENCES toko(id),
  to_toko_id INTEGER REFERENCES toko(id),
  transfer_request_id INTEGER REFERENCES stock_transfer_requests(id), -- null for direct
  
  -- Type
  movement_type VARCHAR(20), -- 'transfer_request', 'transfer_direct', 'initial_stock'
  
  -- Actor
  moved_by INTEGER REFERENCES users(id),
  
  -- Timestamp
  moved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- Note
  note TEXT
);
```

---

### **TOKO GROUPING - SPC CONTEXT**

#### **SPC = Store with Multiple Branches**
```
Contoh SPC:
├─ SPC "Transmart" (1 owner, banyak cabang)
│   ├─ Cabang: Transmart MTC
│   ├─ Cabang: Transmart Panakukkang
│   └─ Cabang: Transmart Lippo
│
├─ SPC "Electronic City" (1 owner, banyak cabang)
│   ├─ Cabang: EC Mall A
│   └─ Cabang: EC Mall B
│
└─ Toko Independen (1 toko saja)
    └─ Toko Mandiri XYZ

Transfer sering terjadi di dalam SPC (antar cabang)
= Perlu tracking 100% akurat!
```

#### **Transfer Rules:**
```
✅ Transfer dalam SPC (antar cabang) = ALWAYS ALLOWED
   └─ Approval antar promotor saja
   └─ Tidak perlu SATOR

✅ Transfer antar SPC berbeda = ALLOWED
   └─ Sama prosesnya
   └─ Tracking tetap lengkap

✅ SEMUA transfer harus tercatat (no exception!)
```

#### **Database:**
```sql
-- Toko Groups (SPC)
CREATE TABLE toko_groups (
  id SERIAL PRIMARY KEY,
  nama_grup VARCHAR(255) NOT NULL, -- "Transmart", "Electronic City"
  is_spc BOOLEAN DEFAULT true, -- SPC = multi-branch store
  owner_name VARCHAR(255), -- Optional: nama owner
  contact_info TEXT, -- Optional: contact
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Update toko table
ALTER TABLE toko ADD COLUMN grup_id INTEGER REFERENCES toko_groups(id);

-- Index for group queries
CREATE INDEX idx_toko_grup ON toko(grup_id);
```

---

## 🎯 STOCK ACCURACY SYSTEM (CRITICAL!)

### **WHY ACCURACY MATTERS:**
```
┌─────────────────────────────────────────────────────────────┐
│ Problem: Stok tidak akurat                                  │
│                                                             │
│ ↓                                                           │
│                                                             │
│ Order Recommendation SALAH:                                 │
│ - Sistem recommend order Y400 (karena stok = 0)            │
│ - Padahal stok = 5 (transferred tapi tidak tercatat)       │
│ - Toko over-order → Modal nganggur                         │
│                                                             │
│ OR:                                                         │
│ - Sistem tidak recommend order (karena stok = 5)           │
│ - Padahal stok = 0 (transferred keluar tidak tercatat)    │
│ - Toko out-of-stock → Lost sales                           │
│                                                             │
│ ↓                                                           │
│                                                             │
│ SOLUTION: 100% Stock Accuracy via IMEI Tracking            │
└─────────────────────────────────────────────────────────────┘
```

### **ACCURACY RULES:**
```
1. SETIAP IMEI harus punya lokasi pasti (toko_id)
2. SETIAP perpindahan IMEI harus tercatat (movement_log)
3. TIDAK ADA stok yang "hilang" atau "muncul tiba-tiba"
4. SEMUA perubahan = logged (audit trail)
```

### **STOCK CALCULATION FORMULA:**
```
Stok Toko X pada Hari H:

  Stok Awal (H-1)
+ Incoming Transfer (from other toko)
+ Incoming from Gudang (new stock)
- Outgoing Transfer (to other toko)
- Sold (IMEI sold)
- Chip Activation (status change, still in stock)
──────────────────────────────────────
= Stok Valid Hari H

HARUS ALWAYS MATCH dengan physical count!
```

### **TRACKING MECHANISMS:**

#### **1. Movement Log (Every IMEI Change)**
```sql
-- Every time IMEI moves, log it
INSERT INTO stock_movement_log (
  imei,
  from_toko_id,  -- NULL if new stock
  to_toko_id,
  movement_type, -- 'initial', 'transfer_in', 'transfer_out', 'sold'
  moved_by,
  moved_at
) VALUES (...);

Movement Types:
├─ 'initial'      - Barang baru masuk dari gudang
├─ 'transfer_in'  - Terima dari toko lain
├─ 'transfer_out' - Kirim ke toko lain
├─ 'sold'         - Terjual (end state)
├─ 'chip'         - Chip activation (status change)
└─ 'adjustment'   - Manual adjustment (with reason)
```

#### **2. Daily Stock Snapshot**
```sql
-- Auto-capture daily stock per toko (for historical)
CREATE TABLE stock_daily_snapshot (
  id SERIAL PRIMARY KEY,
  toko_id INTEGER REFERENCES toko(id),
  tanggal DATE NOT NULL,
  
  -- Counts per condition
  fresh_count INTEGER DEFAULT 0,
  chip_count INTEGER DEFAULT 0,
  display_count INTEGER DEFAULT 0,
  total_count INTEGER DEFAULT 0,
  
  -- Value
  total_value DECIMAL(15,2),
  
  -- Capture time
  captured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  UNIQUE(toko_id, tanggal)
);

-- Auto-populated by daily cron job (midnight)
```

#### **3. Stock Reconciliation**
```
Periodic Physical Count vs System Count:

SATOR Schedule:
├─ Weekly spot-check (random toko)
├─ Monthly full count (all toko)
└─ Quarterly audit (formal)

Process:
1. Promotor physical count
2. Compare with system
3. If mismatch:
   a. Find missing IMEIs
   b. Create adjustment record
   c. Investigate cause
   d. Update system
4. Sign-off by promotor
```

---

## 📊 INTEGRATION: ORDER RECOMMENDATION

### **Flow:**
```
┌─────────────────────────────────────────────────────────────┐
│ STOCK DATA (100% Accurate)                                  │
│ ├─ Fresh stock per toko per produk                         │
│ ├─ Transfer in-progress                                     │
│ └─ Sales velocity (7-day average)                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ ORDER RECOMMENDATION ENGINE                                 │
│                                                             │
│ For each Toko x Product:                                    │
│                                                             │
│ Current Stock: 3 unit                                       │
│ + In Transit: 2 unit                                        │
│ = Available Soon: 5 unit                                    │
│                                                             │
│ Sales Velocity: 2 unit/day                                  │
│ Days of Stock: 5 / 2 = 2.5 days                            │
│                                                             │
│ Safety Stock: 5 days                                        │
│ Needed: 5 days × 2 unit/day = 10 unit                      │
│                                                             │
│ RECOMMENDATION: Order 10 - 5 = 5 unit                       │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ OUTPUT: Order List per Toko                                 │
│                                                             │
│ Toko: Transmart MTC                                         │
│ ┌────────────────────────────┬───────┬──────────┐          │
│ │ Product                    │ Stock │ Order    │          │
│ ├────────────────────────────┼───────┼──────────┤          │
│ │ Y400 8/256 Purple          │ 3     │ 5 unit   │          │
│ │ V60 Lite 5G Black          │ 0     │ 8 unit   │          │
│ │ Y19s PRO 4/128 Silver      │ 10    │ 0 unit ✓│          │
│ └────────────────────────────┴───────┴──────────┘          │
└─────────────────────────────────────────────────────────────┘

Accurate stock = Accurate recommendation!
```

### **SPC Special Case:**
```
SPC dengan multiple cabang:

SATOR View:
┌─────────────────────────────────────────────────────────────┐
│ SPC: Transmart (3 Cabang)                                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Y400 8/256 Purple - TOTAL SPC: 15 unit                     │
│ ├─ MTC: 3 unit                                              │
│ ├─ Panakukkang: 8 unit ⚠️ (over-stock)                     │
│ └─ Lippo: 4 unit                                            │
│                                                             │
│ INSIGHT:                                                    │
│ ├─ Panakukkang punya banyak, MTC kurang                    │
│ ├─ Suggest: Internal transfer before new order              │
│ └─ [Auto-Suggest Transfer: Panakukkang → MTC 3 unit]       │
│                                                             │
│ ORDER RECOMMENDATION (After Internal Balance):              │
│ ├─ MTC: 0 unit (akan dapat transfer)                       │
│ ├─ Panakukkang: 0 unit (over-stock)                        │
│ └─ Lippo: 3 unit (butuh tambahan)                          │
│ ├─ TOTAL NEW ORDER: 3 unit only!                           │
│                                                             │
│ Value: Avoid over-ordering, optimize internal stock!        │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 ALERT SYSTEM (Stock Related)

### **Alerts:**
```
1. LOW STOCK ALERT
   └─ Toko X produk Y stock < safety level
   └─ Notify: Promotor, SATOR

2. TRANSFER PENDING
   └─ Transfer request belum di-approve > 24 jam
   └─ Notify: Promotor pengirim + penerima

3. STOCK MISMATCH
   └─ System count ≠ Physical count (reconciliation)
   └─ Notify: SATOR, Admin

4. SPC IMBALANCE
   └─ Cabang A over-stock, Cabang B low-stock (same SPC)
   └─ Suggest: Internal transfer
   └─ Notify: SATOR

5. TRANSFER ANOMALY
   └─ Unusual transfer pattern (e.g., same IMEI transferred 3x in a week)
   └─ Notify: SATOR (potential issue)
```

---

### **UI MOCKUP: Search Stock Other Stores**

```
┌─────────────────────────────────────────────────────────────┐
│ 🔍 CARI STOK DI TOKO LAIN                                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Produk: [Y400 8/256 Purple________▼]                       │
│                                                             │
│ Hasil Pencarian:                                            │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ 🏪 Transmart MTC (Grup: Transmart)                      ││
│ │ ├─ Fresh: 5 unit                                        ││
│ │ ├─ Chip: 2 unit                                         ││
│ │ └─ [Request Transfer]                                   ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ 🏪 Electronic City Mall A                                ││
│ │ ├─ Fresh: 3 unit                                        ││
│ │ ├─ Chip: 0 unit                                         ││
│ │ └─ [Request Transfer]                                   ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ 🏪 Panakukkang (Grup: Transmart) - SAME GROUP ⭐       ││
│ │ ├─ Fresh: 8 unit                                        ││
│ │ ├─ Chip: 1 unit                                         ││
│ │ └─ [Request Transfer] [Priority!]                       ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### **UI MOCKUP: Transfer Request Form**

```
┌─────────────────────────────────────────────────────────────┐
│ 📦 REQUEST TRANSFER                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Dari: Transmart MTC (Stock: 5 Fresh, 2 Chip)               │
│ Ke: Toko Saya (Panakukkang)                                 │
│                                                             │
│ Produk: Y400 8/256 Purple                                   │
│ Jumlah: [2___] unit                                         │
│                                                             │
│ Kondisi yang diminta:                                       │
│ ☑ Fresh                                                     │
│ ☐ Chip                                                      │
│                                                             │
│ Catatan (optional):                                         │
│ [Customer lagi tunggu, butuh hari ini________]             │
│                                                             │
│                    [Cancel] [Submit Request]                │
└─────────────────────────────────────────────────────────────┘
```

---

### **UI MOCKUP: Incoming Transfer Request**

```
┌─────────────────────────────────────────────────────────────┐
│ 🔔 TRANSFER REQUEST                                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Ahmad (Panakukkang) minta:                                  │
│ ├─ Produk: Y400 8/256 Purple                               │
│ ├─ Jumlah: 2 unit Fresh                                    │
│ └─ Catatan: "Customer lagi tunggu, butuh hari ini"         │
│                                                             │
│ Stok kamu:                                                  │
│ ├─ Fresh: 5 unit                                           │
│ └─ Chip: 2 unit                                            │
│                                                             │
│ Pilih IMEI untuk transfer:                                  │
│ ☑ IMEI: 35912...456 (Fresh) - masuk 2 hari lalu           │
│ ☑ IMEI: 35912...457 (Fresh) - masuk 3 hari lalu           │
│ ☐ IMEI: 35912...458 (Fresh) - baru masuk hari ini         │
│                                                             │
│                    [Reject] [Approve (2 unit)]             │
└─────────────────────────────────────────────────────────────┘
```

---

### **REPORTING: Stock Accuracy**

```
Report: STOCK VALIDITY CHECK

Toko: Transmart Panakukkang
Date: 8 Januari 2026

SUMMARY:
├─ Total IMEI Records: 125 unit
├─ Last Physical Count: 123 unit (6 Jan 2026)
├─ Discrepancy: 2 unit ⚠️
│
├─ Incoming Transfers (7-8 Jan): +5 unit
├─ Outgoing Transfers (7-8 Jan): -2 unit
├─ Sales (7-8 Jan): -3 unit
│
└─ Expected Current: 123 + 5 - 2 - 3 = 123 unit ✅

TRANSFER HISTORY (Last 7 Days):
┌────────┬─────────┬────────────┬──────┬────────┐
│ Date   │ Type    │ From/To    │ Qty  │ Status │
├────────┼─────────┼────────────┼──────┼────────┤
│ 8 Jan  │ IN      │ from MTC   │ 2    │ ✅     │
│ 7 Jan  │ IN      │ from Lippo │ 3    │ ✅     │
│ 7 Jan  │ OUT     │ to EC Mall │ 2    │ ✅     │
│ 5 Jan  │ IN      │ from MTC   │ 4    │ ✅     │
└────────┴─────────┴────────────┴──────┴────────┘
```

| Action | Bonus Paid? | Amount |
|--------|-------------|--------|
| Fresh → Sold | ✅ Yes | Normal (range/flat/ratio) |
| Fresh → Chip | ✅ Yes | Normal (range/flat/ratio) |
| Chip → Sold | ❌ No | Rp 0 (already paid) |
| Display → Chip | ✅ Yes | TBD (normal or reduced?) |
| Display → Sold | ❌ N/A | Display should not be sold directly |

---

## 📦 PRODUCT FLAG: CUCI GUDANG

### **Location:** Master Products table (bukan stock condition)

```sql
products table:
├─ is_cuci_gudang BOOLEAN DEFAULT false
└─ cuci_gudang_since DATE

Example:
├─ Y19: is_cuci_gudang = true, since = 2025-11-01
└─ Y19s: is_cuci_gudang = false
```

### **Rules:**
```
✅ Harga: SAMA (no discount, unless promo)
✅ Bonus: SAMA (normal calculation)
✅ Target: SAMA (masuk perhitungan)

Cuci Gudang hanya FLAG untuk:
├─ Reporting: "Produk lama yang perlu dihabiskan"
├─ Priority: Push sales untuk model lama
└─ Planning: Stop restock, focus clearance
```

---

## ❓ 1 PERTANYAAN PENDING

### **Display → Chip Bonus:**
```
Jika display unit mau dijual (convert to chip):

Option A: Bonus NORMAL (sama dengan fresh → chip)
Option B: Bonus REDUCED (e.g., 50%)
Option C: Bonus NONE (display = no bonus ever)

❓ Mana yang dipakai?
```

---

## ✅ SUMMARY - LOCKED RULES

```
STOCK CONDITIONS (3):
├─ Fresh: Bonus saat SOLD atau saat CHIP
├─ Chip: Bonus SUDAH DIBAYAR, no more bonus
└─ Display: No bonus (demo unit)

PRICING:
└─ SEMUA SAMA (dari master product, no discount)

CUCI GUDANG:
└─ Product flag, bukan stock condition
└─ Harga & bonus SAMA

CRITICAL RULE:
└─ 1 IMEI = 1 BONUS (tidak boleh dobel!)
```

---

**Status:** Stock Condition Rules - 95% LOCKED ✅  
**Pending:** Display → Chip bonus rule
