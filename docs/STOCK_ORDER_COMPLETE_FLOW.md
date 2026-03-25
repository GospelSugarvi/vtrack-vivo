# 📦 STOCK & ORDER COMPLETE FLOW
**Date:** 8 Januari 2026  
**Status:** Planning - LOCKED ✅  
**Purpose:** Complete flow dari stok gudang → order → stok toko → penjualan

---

## 🎯 OVERVIEW: SISTEM INI BUKAN GUDANG

### **Yang Termasuk Sistem Ini:**
```
✅ Stok TOKO (per IMEI, tracked)
✅ Stok GUDANG (input manual oleh SATOR, reference only)
✅ Rekomendasi Order (generate by SATOR)
✅ Order Tracking (approve/reject by toko)
✅ Stock Transfer (antar toko)
✅ Penjualan & Bonus
```

### **Yang TIDAK Termasuk:**
```
❌ Gudang management system (terpisah)
❌ Order processing ke gudang (pakai app resmi)
❌ Delivery tracking dari gudang (external)
```

---

## 📊 DAILY FLOW (Senin - Sabtu)

### **MORNING: SATOR Check & Order**

```
06:00 - 09:00 SATOR WORKFLOW

┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Check Stok Gudang (Input)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ SATOR lihat stok gudang (dari App Resmi atau Screenshot):   │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Y400 8/256 Purple:  25 unit                             ││
│ │ Y400 8/256 Green:   30 unit                             ││
│ │ Y19s PRO 4/128:     100 unit                            ││
│ │ V60 Lite 5G:        15 unit                             ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ Input ke sistem (manual atau AI image parsing):             │
│ → Save to: stok_gudang_harian                               │
│ → Purpose: Reference untuk rekomendasi order               │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 2: Check Stok Toko (Automatic dari System)            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ System otomatis aggregate dari IMEI records:                │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ TOKO: Transmart MTC                                     ││
│ │ Y400 8/256 Purple: 1 unit (Fresh) ⚠️ LOW               ││
│ │ Y400 8/256 Green:  0 unit ❌ EMPTY                      ││
│ │ Y19s PRO 4/128:    5 unit ✅ OK                         ││
│ │ V60 Lite 5G:       2 unit ⚠️ LOW                       ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ Source: COUNT(stok WHERE toko_id = X AND is_sold = false)  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 3: Generate Rekomendasi Order                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ENGINE CALCULATION:                                         │
│                                                             │
│ For each Toko x Product:                                    │
│ ├─ Stok Toko: 1 unit                                       │
│ ├─ Stok Gudang: 25 unit (ada!)                             │
│ ├─ Stok Minimal: 3 unit (Grade A, Y-series)                │
│ ├─ Kebutuhan: 3 - 1 = 2 unit                               │
│ └─ Rekomendasi: MIN(2, 25) = 2 unit ✅                     │
│                                                             │
│ CRITICAL RULES:                                             │
│ ├─ Stok Gudang = 0 → SKIP (jangan recommend!)              │
│ ├─ Stok Toko >= Minimal → No order needed                  │
│ └─ Order Qty = MIN(Kebutuhan, Stok Gudang)                 │
│                                                             │
│ OUTPUT:                                                     │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ REKOMENDASI: Transmart MTC                              ││
│ │ Y400 8/256 Purple: 2 unit @ Rp 3.499.000 = Rp 6.998.000││
│ │ Y400 8/256 Green:  3 unit @ Rp 3.499.000 = Rp 10.497.000│
│ │ V60 Lite 5G Black: 3 unit @ Rp 4.999.000 = Rp 14.997.000│
│ │ ──────────────────────────────────────────────────────  ││
│ │ TOTAL: 8 unit | Rp 32.492.000                           ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ [Send WhatsApp to Owner] [Copy Text] [Save Draft]          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 4: Send Rekomendasi ke Toko                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Via WhatsApp/Discord ke Owner Toko:                         │
│ "Pak Budi, rekomendasi order hari ini:                      │
│  - Y400 8/256 Purple: 2 unit                                │
│  - Y400 8/256 Green: 3 unit                                 │
│  - V60 Lite 5G Black: 3 unit                                │
│  Total: Rp 32.492.000                                       │
│                                                             │
│  Gimana pak, order?"                                        │
│                                                             │
│ → Status: "Sent to Toko"                                    │
│ → Waiting for approval                                      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 5: Toko Approve/Reject (Outside App)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Owner Toko via WhatsApp:                                    │
│ ├─ ✅ "OK, order semua"                                    │
│ ├─ ⏸️ "Y400 aja, V60 nanti"                               │
│ └─ ❌ "Tidak dulu, uang tipis"                             │
│                                                             │
│ SATOR update status di sistem:                              │
│ → Approved / Partially Approved / Rejected                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ STEP 6: Input di App Resmi + Record di Sistem Ini          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ A. SATOR input di APP RESMI (actual order ke gudang)       │
│    → Ini yang trigger pengiriman barang                     │
│                                                             │
│ B. SATOR update di sistem ini:                              │
│    → Status: "Submitted to Warehouse"                       │
│    → For tracking & achievement calculation                 │
└─────────────────────────────────────────────────────────────┘
```

---

### **DAYTIME: Promotor Stock Input**

```
SAAT BARANG SAMPAI DI TOKO

┌─────────────────────────────────────────────────────────────┐
│ Promotor: Input Stok Masuk                                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Barang dari gudang sampai → Promotor scan IMEI              │
│                                                             │
│ Flow:                                                       │
│ 1. Pilih kondisi: [Ada barang baru masuk]                  │
│ 2. Scan IMEI satu-satu:                                     │
│    ├─ IMEI: 35912...001 → Y400 8/256 Purple (detected)     │
│    ├─ IMEI: 35912...002 → Y400 8/256 Purple (detected)     │
│    └─ IMEI: 35912...003 → V60 Lite 5G Black (detected)     │
│ 3. Submit                                                   │
│                                                             │
│ System:                                                     │
│ → Create stok record per IMEI                               │
│ → tipe_stok = "fresh"                                       │
│ → toko_id = promotor's toko                                 │
│ → Send notification to SATOR (Discord/App)                  │
│                                                             │
│ NO APPROVAL NEEDED!                                         │
│ Just input → notification → done                            │
└─────────────────────────────────────────────────────────────┘
```

---

### **SELLING: Normal Sale or Chip**

```
PROMOTOR JUAL BARANG

┌─────────────────────────────────────────────────────────────┐
│ OPTION 1: Normal Sale (Fresh → Sold)                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 1. Promotor pilih: "Input Penjualan"                       │
│ 2. Scan IMEI: 35912...001                                   │
│ 3. System detect:                                           │
│    ├─ Product: Y400 8/256 Purple                           │
│    ├─ Status: Fresh ✅                                      │
│    └─ Harga: Rp 3.499.000                                   │
│ 4. Submit                                                   │
│                                                             │
│ System:                                                     │
│ → Mark: is_sold = true                                      │
│ → Calculate bonus: Rp 45.000                                │
│ → Add to promotor's monthly sales                           │
│ → Update target achievement                                  │
│ → Send notification (Discord)                                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ OPTION 2: Chip Activation (Fresh → Chip)                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Use case:                                                   │
│ ├─ Customer mau lihat isi box                              │
│ ├─ Customer mau test sebelum beli                          │
│ └─ Promo khusus (dengan approval)                          │
│                                                             │
│ 1. Promotor pilih: "Chip Barang"                           │
│ 2. Scan IMEI: 35912...002                                   │
│ 3. Pilih alasan: [Customer mau test ▼]                     │
│ 4. REQUEST to SATOR for approval                            │
│                                                             │
│ SATOR approve via app:                                      │
│ → Mark: tipe_stok = "chip"                                  │
│ → Mark: bonus_paid = true                                   │
│ → Calculate bonus: Rp 45.000 (dibayar saat ini!)           │
│ → Stock still exists (tidak hilang)                         │
│                                                             │
│ LATER: Chip → Sold                                          │
│ → Bonus = Rp 0 (sudah dibayar saat chip)                   │
│ → Stock removed (is_sold = true)                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🗃️ DATA SOURCES

### **1. Stok Gudang (Manual Input by SATOR)**

```sql
-- SATOR input setiap pagi
CREATE TABLE stok_gudang_harian (
  id SERIAL PRIMARY KEY,
  produk_id INTEGER REFERENCES products(id),
  tanggal DATE NOT NULL,
  
  -- Stock counts
  stok_gudang INTEGER NOT NULL DEFAULT 0,
  stok_otw INTEGER DEFAULT 0, -- On the way
  
  -- Status (auto-calculated)
  status VARCHAR(20), -- 'kosong', 'tipis', 'cukup'
  
  -- Metadata
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id),
  
  UNIQUE(produk_id, tanggal)
);

-- Purpose: Reference untuk Order Recommendation
-- NOT the actual warehouse system!
```

### **2. Stok Toko (Auto from IMEI Records)**

```sql
-- View for stok per toko
CREATE VIEW v_stok_toko AS
SELECT 
  s.toko_id,
  s.produk_id,
  p.nama_produk,
  p.varian,
  s.warna,
  COUNT(*) FILTER (WHERE s.tipe_stok = 'fresh') as fresh_count,
  COUNT(*) FILTER (WHERE s.tipe_stok = 'chip') as chip_count,
  COUNT(*) FILTER (WHERE s.tipe_stok = 'display') as display_count,
  COUNT(*) as total_count
FROM stok s
JOIN products p ON s.produk_id = p.id
WHERE s.is_sold = false
GROUP BY s.toko_id, s.produk_id, p.nama_produk, p.varian, s.warna;

-- This is ALWAYS accurate (based on actual IMEI records)
```

---

## 🔄 ORDER STATUSES

```
1. "Draft"
   └─ Rekomendasi dibuat, belum dikirim

2. "Sent to Toko"
   └─ Sudah kirim WhatsApp ke owner

3. "Approved"
   └─ Toko setuju order

4. "Partially Approved"
   └─ Toko setuju sebagian (qty adjusted)

5. "Rejected"
   └─ Toko tolak (uang tidak cukup, dll)

6. "Pending"
   └─ Toko minta negotiation

7. "Submitted"
   └─ Sudah input di App Resmi

8. "Delivered"
   └─ Barang sudah sampai toko

9. "Received"
   └─ Promotor sudah scan IMEI (masuk ke stok)
```

---

## 📱 ADMIN CONTROL FOR STOCK

### **What Admin Can Do:**

```
1. VIEW ALL STOCK
   ├─ All toko stock summary
   ├─ Stock per IMEI (drill-down)
   ├─ Stock movement history
   └─ Anomaly detection

2. STOCK ADJUSTMENT
   ├─ Manual adjustment (with reason)
   ├─ Discrepancy resolution
   ├─ Lost/Found IMEI handling
   └─ Audit log (who, when, why)

3. STOK MINIMAL SETTINGS
   ├─ Set default minimal per category/tier/grade
   ├─ Override per toko-product
   └─ Bulk update

4. GUDANG STOCK MANAGEMENT
   ├─ Approve SATOR's daily input
   ├─ Override if needed
   └─ Historical view

5. ORDER OVERSIGHT
   ├─ View all orders across SATORs
   ├─ Approval rate monitoring
   ├─ Sell-in achievement tracking
   └─ Export reports

6. TRANSFER OVERSIGHT
   ├─ View all transfer requests
   ├─ Transfer history
   ├─ Anomaly alerts
   └─ SPC balance monitoring
```

### **Admin Dashboard (Stock Section):**

```
┌─────────────────────────────────────────────────────────────┐
│ 📦 ADMIN: STOCK MANAGEMENT                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ SUMMARY (Today):                                            │
│ ├─ Total Stock (All Toko): 1,250 unit | Rp 5.2B           │
│ ├─ Low Stock Alerts: 15 products in 8 toko ⚠️              │
│ ├─ Pending Orders: 12 | Rp 156M                            │
│ └─ Transfers Today: 23 (5 pending approval)                │
│                                                             │
│ QUICK ACTIONS:                                              │
│ ├─ [View Low Stock] [View Pending Orders]                  │
│ ├─ [View Transfer Requests]                                 │
│ ├─ [Stock Adjustment]                                       │
│ └─ [Export Report]                                          │
│                                                             │
│ ALERTS:                                                     │
│ ├─ ⚠️ MTC: Y400 8/256 Purple - Only 1 unit left           │
│ ├─ ⚠️ Panakukkang: V60 Lite - Out of stock                │
│ ├─ 🔄 SPC Imbalance: Transmart (MTC low, Lippo high)      │
│ └─ ❓ Discrepancy: EC Mall A - 2 IMEI not found            │
│                                                             │
│ [View All Alerts]                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 CRITICAL INTEGRATION POINTS

### **1. Stock ↔ Order Recommendation**
```
Order Recommendation DEPENDS ON:
├─ Stok Toko (accurate from IMEI)
├─ Stok Gudang (SATOR's daily input)
├─ Stok Minimal (Admin settings)
└─ Sales Velocity (historical data)

If stock data wrong → Recommendation wrong!
```

### **2. Stock ↔ Bonus Calculation**
```
Bonus Calculation DEPENDS ON:
├─ IMEI sold/chipped
├─ Product price (from master)
├─ Promotor status (Official/Training)
└─ bonus_paid flag (prevent double)

If IMEI tracking wrong → Bonus double/missed!
```

### **3. Stock ↔ Target Achievement**
```
Target Achievement DEPENDS ON:
├─ Sales count (from sold IMEIs)
├─ Sales value (IMEI × harga)
├─ Product category (Tipe Fokus)
└─ Period (monthly)

If sales tracking wrong → Achievement wrong!
```

---

## ✅ SUMMARY

### **Flow Lengkap:**
```
1. SATOR input stok gudang (pagi)
2. SATOR lihat stok toko (auto from system)
3. SATOR generate rekomendasi order
4. SATOR kirim ke toko via WhatsApp
5. Toko approve/reject
6. SATOR input di App Resmi (actual order)
7. SATOR update status di sistem ini
8. Barang sampai → Promotor scan IMEI
9. Stok toko terupdate otomatis
10. Promotor jual → scan IMEI → Bonus calculated

SEMUA TERCATAT!
```

### **Key Points:**
```
✅ Gudang = Reference only (external system)
✅ Toko Stock = 100% accurate (IMEI tracking)
✅ Order = Tracking only (actual order via App Resmi)
✅ Transfer = Fully tracked (antar toko)
✅ Bonus = 1 IMEI = 1 Bonus (no double)
✅ Admin = Full visibility & control
```

---

**Status:** Stock & Order Flow - 100% LOCKED ✅
