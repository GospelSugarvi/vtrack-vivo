# 📦 SISTEM SELL-IN - ANALISIS LENGKAP & SIMPLIFIKASI

**Tanggal:** 2 Januari 2026  
**Status:** KOMPLEKS - Perlu Disederhanakan  
**Tujuan:** Membantu SATOR push order cepat, tersistem, tidak sembarangan

---

## 🎯 APA ITU SELL-IN?

### **Definition:**
**SELL-IN** = Order barang DARI gudang pusat KE toko

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   GUDANG    │ ──────▶ │    TOKO     │ ──────▶ │  CUSTOMER   │
│   PUSAT     │ SELL-IN │  (Retail)   │ SELL-OUT│    (End)    │
└─────────────┘         └─────────────┘         └─────────────┘
```

**SELL-IN = Restocking**
**SELL-OUT = Actual Sales** (yang sudah kita track di promotor)

---

## ⚠️ KENAPA INI PENTING?

### **1. SATOR & SPV Punya Target Sell-In!**

```
Target Sell-In = Berapa banyak barang yang harus di-push ke toko

Example:
Target Sell-In Jan 2026: Rp 500 juta
= SATOR harus push order total 500jt ke semua tokonya

Achievement dihitung dari:
- Order yang di-approved
- BUKAN dari penjualan actual
```

### **2. Stok Toko Harus Selalu Ada!**

```
❌ Problem: Stok toko habis
   → Customer datang, tidak ada barang
   → Lost sales!
   → Target sell-out tidak tercapai

✅ Solution: Deteksi auto + push order
   → Stok hampir habis → alert!
   → SATOR push order segera
   → Toko selalu ready
```

### **3. Avoid Over/Under Stock:**

```
❌ UNDER STOCK:
   Toko kehabisan barang
   → Missed opportunity
   → Customer beli di kompetitor

❌ OVER STOCK:
   Toko kelebihan barang
   → Modal stuck
   → Storage cost
   → Risk obsolescence (HP model lama)

✅ OPTIMAL:
   Stock = Stok Minimal + Safety Buffer
   → Always available
   → Modal efficient
```

---

## 🔄 WORKFLOW SAAT INI (KOMPLEKS!)

### **Flow Lengkap:**

```
1. DETEKSI KEBUTUHAN
   ├─ Manual: SATOR cek dashboard stok
   ├─ Auto: System detect stok < minimal
   └─ Rekomendasi: AI generate based on sales velocity

2. GENERATE REKOMENDASI ORDER
   ├─ SATOR pilih toko
   ├─ System calculate kebutuhan:
   │  Logic: qty = MIN(stok_minimal - stok_toko, stok_gudang)
   ├─ Generate list produk + qty
   └─ SATOR bisa edit manual

3. CREATE ORDER (Form Order)
   ├─ SATOR buat order dari rekomendasi
   ├─ Atau input manual product by product
   ├─ Status: 'pending' → 'submitted'
   └─ Save to database

4. VERIFIKASI ORDER (Daily)
   ├─ SATOR review semua submitted orders
   ├─ Decision per order:
   │  ✅ Approve → kirim ke gudang
   │  ❌ Reject → cancel order
   └─ Must process ALL orders before end of day

5. SEND DAILY REPORT
   ├─ After all orders processed
   ├─ Summary: Total approved, Total amount, Rejected count
   ├─ Send to Discord (notify warehouse)
   └─ Create SellInDailyReport record

6. HISTORY & TRACKING
   ├─ View past orders
   ├─ Filtering (date, toko, status)
   ├─ Export Excel/PDF
   └─ Performance tracking
```

**Total Steps:** 6 major stages  
**Problem:** TOO MANY STEPS! ⚠️

---

## 📊 DATABASE MODELS

### **1. Order (Main Table)**

```sql
CREATE TABLE order (
  id BIGSERIAL PRIMARY KEY,
  toko_id BIGINT REFERENCES toko(id),
  sales_id BIGINT REFERENCES users(id),  -- SATOR yang buat order
  tanggal_order DATE,
  status VARCHAR(20),  -- 'pending', 'submitted', 'approved', 'rejected'
  total_order DECIMAL(15,2),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Status Flow:**
```
'pending'    → Order baru dibuat, masih draft
'submitted'  → Order sudah disubmit, menunggu approval
'approved'   → Order di-approve, siap kirim
'rejected'   → Order di-reject, tidak jadi
```

### **2. OrderItem (Detail)**

```sql
CREATE TABLE order_item (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT REFERENCES order(id),
  produk_id BIGINT REFERENCES produk(id),
  qty INTEGER,
  harga_modal INTEGER,
  subtotal INTEGER,
  created_at TIMESTAMP
);
```

### **3. RekomendasiOrder (AI Generated)**

```sql
CREATE TABLE rekomendasi_order (
  id BIGSERIAL PRIMARY KEY,
  produk_id BIGINT REFERENCES produk(id),
  toko_id BIGINT REFERENCES toko(id),
  qty_direkomendasikan INTEGER,
  tanggal_rekomendasi DATE,
  status VARCHAR(20),  -- 'pending', 'diproses', 'dikirim', 'selesai'
  catatan TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Purpose:** Save AI-generated recommendations

### **4. SellInDailyReport (Summary)**

```sql
CREATE TABLE sell_in_daily_report (
  id BIGSERIAL PRIMARY KEY,
  sator_id BIGINT REFERENCES users(id),
  tanggal DATE,
  has_orders BOOLEAN,  -- True jika ada order, False jika tidak
  total_orders INTEGER,
  total_approved INTEGER,
  total_rejected INTEGER,
  total_amount DECIMAL(15,2),
  discord_message_sent BOOLEAN,
  created_at TIMESTAMP,
  
  UNIQUE(sator_id, tanggal)  -- One report per SATOR per day
);
```

**Purpose:** Daily summary yang dikirim ke Discord

---

## 🤖 REKOMENDASI ORDER (AI Logic)

### **Calculation Logic:**

```python
def calculate_rekomendasi(toko, produk):
    # 1. Get stok gudang (from StokGudangHarian)
    stok_gudang = StokGudangHarian.objects.filter(
        produk=produk,
        tanggal=today
    ).first().stok_gudang
    
    # 2. Get stok toko (count IMEIs)
    stok_toko = Stok.objects.filter(
        toko=toko,
        produk=produk,
        tipe_stok__in=['fresh', 'chip']
    ).count()
    
    # 3. Get stok minimal (from StokMinimalToko or standard)
    stok_minimal = get_stok_minimal(toko.grade, produk.harga_srp)
    
    # 4. Calculate kebutuhan
    kebutuhan = stok_minimal - stok_toko
    
    # 5. Qty rekomendasi = MIN(kebutuhan, stok_gudang)
    if kebutuhan <= 0:
        return 0  # Tidak perlu order
    
    if stok_gudang <= 0:
        return 0  # Gudang kosong
    
    qty_rekomendasi = min(kebutuhan, stok_gudang)
    return qty_rekomendasi
```

### **Stok Minimal Standard:**

```python
# Based on Toko Grade & Product Price

STOK_MINIMAL = {
    'A': {  # Toko besar
        '1-2jt':   3 unit,
        '2-3jt':   3 unit,
        '3-4jt':   2 unit,
        '4-6jt':   2 unit,
        '>6jt':    1 unit,
    },
    'B': {  # Toko sedang
        '1-2jt':   2 unit,
        '2-3jt':   2 unit,
        '3-4jt':   1 unit,
        '4-6jt':   1 unit,
        '>6jt':    1 unit,
    },
    'C': {  # Toko kecil
        '1-2jt':   1 unit,
        '2-3jt':   1 unit,
        '3-4jt':   1 unit,
        '4-6jt':   1 unit,
        '>6jt':    1 unit,
    },
    'D': {  # Toko sangat kecil
        '1-2jt':   1 unit,
        '2-3jt':   1 unit,
        '3-4jt':   1 unit,
        '4-6jt':   1 unit,
        '>6jt':    1 unit,
    },
}
```

**Logic:** Toko besar perlu stok lebih banyak

---

## 📱 HALAMAN & PAGE FLOW (SAAT INI)

### **1. Sell-In Dashboard (Landing)**
```
URL: /sales/dashboard/sell-in/

Content:
- Quick links to sub-menus
- Today's summary
- Navigation tiles

Sub-menus:
├─ Verifikasi Order
├─ History Order
├─ Rekomendasi Order
└─ Form Order Manual
```

### **2. Rekomendasi Order List**
```
URL: /sales/dashboard/rekomendasi-order/

Content:
- List semua toko
- Status: Ada/tidak ada rekomendasi today
- Click toko → Rekomendasi Detail
```

### **3. Rekomendasi Order Detail (Per Toko)**
```
URL: /sales/dashboard/rekomendasi-order/{toko_id}/

Actions:
[Generate Auto] → AI calculate berdasarkan formula
[Edit Manual]   → SATOR ubah qty
[Add Product]   → SATOR tambah produk manual
[Save]          → Save to RekomendasiOrder table
[Import to Order] → Pindah ke Form Order

Table columns:
- Produk
- Stok Gudang
- Stok Toko
- Stok Minimal
- Qty Rekomendasi
- Harga Modal
- Subtotal
```

### **4. Form Order**
```
URL: /sales/dashboard/form-order/

Purpose: Create actual order

Can import from:
- Rekomendasi yang sudah disave
- Input manual satu-satu

Flow:
1. Pilih toko
2. [Import Rekomendasi] atau [Add Manual]
3. Edit qty kalau perlu
4. Preview
5. Submit → status = 'submitted'
```

### **5. Verifikasi Order** ⭐ DAILY TASK
```
URL: /sales/sell-in/verifikasi/

Content:
┌────────────────────────────────────┐
│  📦 VERIFIKASI ORDER - 2 Jan 2026  │
├────────────────────────────────────┤
│  Pending: 5     Approved: 3        │
│  Rejected: 1                       │
├────────────────────────────────────┤
│  Order #001                        │
│  Toko: Transmart MTC               │
│  Sales: NIO                        │
│  Total: Rp 25,000,000 (15 produk)  │
│  [View Detail ▼]                   │
│  [✅ Approve] [❌ Reject]          │
├────────────────────────────────────┤
│  Order #002                        │
│  ...                               │
└────────────────────────────────────┘

Rules:
- Harus approve/reject SEMUA order
- Tidak boleh ada yang pending
- After all processed:
  [📤 Send Daily Report to Discord]
  
- Jika tidak ada order:
  [Confirm: Tidak Ada Order Hari Ini]
```

### **6. History Order**
```
URL: /sales/sell-in/history/

Filters:
- Date range (Today, 7 days, 30 days, Custom)
- Toko filter
- Status filter

Export:
- Excel
- PDF

Permission:
- SATOR: View own orders only
- SPV: View all orders
```

---

## ⚠️ MASALAH WORKFLOW SAAT INI

### **1. TOO MANY STEPS! (6 stages)**

```
Current Flow:
Deteksi → Generate Rekomendasi → Save → Create Order
→ Submit → Verifikasi → Approve → Report

Problem:
- Terlalu panjang
- Banyak page transitions
- Easy to miss steps
```

### **2. Rekomendasi vs Order (Confusing!)**

```
User confusion:
"Rekomendasi sudah saya save, kok masih  harus buat order lagi?"

Current:
Rekomendasi ≠ Order
- Rekomendasi = suggestions only
- Order = actual request

⚠️ Ini membingungkan!
```

### **3. Daily Verifikasi Bottleneck**

```
SATOR harus:
1. Kumpulkan semua order (from all promotor/sales)
2. Review satu-satu (approve/reject)
3. Proses SEMUA sebelum send report
4. Kalau ada yang ketinggalan → error!

Problem:
- Time consuming
- Blocking process
- Risk: Lupa approve → gudang tidak kirim
```

### **4. Stok Detection Not Auto-Triggered**

```
Current:
- SATOR harus manual cek stok
- Open dashboard → lihat stok low
- Manually create rekomendasi/order

⚠️ Should be: AUTO ALERT when stok < minimal!
```

### **5. No Mobile Optimization**

```
SATOR di lapangan, pakai HP:
- Form order: banyak field, tidak mobile-friendly
- Table layout: scroll horizontal terus
- Verifikasi: susah tap approve/reject (kecil)
```

---

## ✅ PROPOSAL SIMPLIFIKASI

### **GOAL: Reduce 6 steps → 3 steps**

### **NEW SIMPLIFIED FLOW:**

```
STEP 1: AUTO DETECTION & ALERT
┌────────────────────────────────────┐
│  ⚠️ STOK ALERT                     │
│  Transmart MTC:                    │
│  - Y19s: 1 unit (minimal: 3)       │
│  - V40: 0 unit (minimal: 2)        │
│                                    │
│  [Quick Order]                     │
└────────────────────────────────────┘

STEP 2: QUICK ORDER (One-Click)
┌────────────────────────────────────┐
│  📦 ORDER CEPAT - MTC              │
│  AI Rekomendasi:                   │
│  ✅ Y19s: 5 unit (Rp 12.5jt)       │
│  ✅ V40: 3 unit (Rp 13.5jt)        │
│                                    │
│  Total: Rp 26 juta                 │
│  [✏️ Edit] [✅ Submit Langsung]    │
└────────────────────────────────────┘

STEP 3: DAILY SUMMARY (Auto at EOD)
┌────────────────────────────────────┐
│  📊 Sell-In Summary - 2 Jan        │
│  Total Orders: 8 (Rp 120 juta)     │
│  Auto-sent to Discord ✅           │
│                                    │
│  [View Detail]                     │
└────────────────────────────────────┘
```

### **Changes:**

**1. Merge Rekomendasi + Order → ONE STEP**
```
OLD:
Generate Rekomendasi → Save → Create Order → Submit

NEW:
Quick Order (Rekomendasi + Order jadi satu!)
- AI auto-calculate
- Show preview
- Edit if needed
- Submit langsung → approved automatically
```

**2. Auto-Approve (Trusted SATOR)**
```
OLD:
Submit → Wait → SATOR Approve → Send

NEW:
Submit → Auto-approved → Send immediately

Rationale:
- SATOR yang buat order = SATOR yang approve
- Kenapa harus approve sendiri? Redundant!
- Trust SATOR decision
```

**3. Auto Alert System**
```
NEW Feature:
- Cron job check stok daily (pagi jam 8)
- If stok < minimal → send notification
- Notification tujuan: SATOR Discord DM
- Include: Quick link to order page
```

**4. Mobile-First UI**
```
Card-based layout:
┌─────────────────────┐
│ 📦 Toko MTC         │
│ Stok Low: 3 produk  │
│                     │
│ [Order →]          │
└─────────────────────┘

One tap → Detail
Big buttons for mobile
Swipe to approve/reject
```

**5. Optional Manual Verifikasi (for SPV)**
```
SPV punya kontrol lebih:
- View all SATOR orders
- Override kalau perlu
- But: Default is auto-approved

SPV bisa:
- Enable "Manual Approval Mode" untuk specific SATOR
- Atau trust all SATORs
```

---

## 🎯 PROPOSED NEW WORKFLOW

### **SATOR Daily Flow (Simplified):**

```
PAGI (08:00):
├─ Buka app
├─ Lihat notif: "3 toko perlu restok"
├─ Tap notification
└─ View list toko dengan stok low

SIANG (11:00):
├─ Pilih toko (e.g. MTC)
├─ AI show rekomendasi:
│  Y19s: 5 unit
│  V40: 3 unit
│  Total: Rp 26jt
├─ Edit kalau perlu (tap qty to change)
├─ [Submit] → Done! ✅
└─ Auto kirim ke gudang via Discord

SORE (17:00):
├─ View summary hari ini
│  Total: 8 orders, Rp 120jt
├─ Confirm kalau correct
└─ Auto-generate daily report to SPV
```

**Total Time:** 5-10 menit (vs 30-60 menit sekarang)

---

## 📊 NEW DATABASE (Simplified)

### **Merge Tables:**

```sql
-- OLD: 2 tables (RekomendasiOrder + Order)
-- NEW: 1 table (Order only!)

CREATE TABLE order (
  id BIGSERIAL PRIMARY KEY,
  toko_id BIGINT,
  sator_id BIGINT,
  tanggal_order DATE,
  
  -- Auto vs Manual
  is_auto_generated BOOLEAN DEFAULT TRUE,
  
  -- Status simplified
  status VARCHAR(20) DEFAULT 'approved',
  -- 'approved', 'cancelled', 'completed'
  
  -- Amounts
  total_order DECIMAL(15,2),
  
  -- Tracking
  created_at TIMESTAMP,
approved_at TIMESTAMP,
  sent_to_warehouse_at TIMESTAMP,
  
  -- Notes
  catatan TEXT
);

-- OrderItem (same)
CREATE TABLE order_item (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT,
  produk_id BIGINT,
  qty INTEGER,
  
  -- Source tracking
  is_auto_recommended BOOLEAN DEFAULT TRUE,
  stok_toko_saat_order INTEGER,
  stok_minimal INTEGER,
  
  harga_modal INTEGER,
  subtotal INTEGER
);
```

### **Why Simplified:**

```
❌ Remove: RekomendasiOrder table
   (No need to save recommendations separately)

❌ Remove: Status 'pending', 'submitted'
   (Auto-approve, no waiting)

✅ Keep: Order + OrderItem (actual orders)

✅ Add: Tracking fields (is_auto_generated, etc)
```

---

## 🔔 NOTIFICATION SYSTEM

### **Daily Auto Alert:**

```python
# Cron job: Every day 08:00 WITA
def check_and_alert_low_stock():
    for sator in Pengguna.objects.filter(peran='Sator'):
        # Get all toko under this SATOR
        tokos = get_sator_tokos(sator)
        
        low_stock_tokos = []
        for toko in tokos:
            # Check stock vs minimal
            low_products = []
            for produk in get_active_products():
                stok_toko = count_stok(toko, produk)
                stok_minimal = get_stok_minimal(toko.grade, produk.harga_srp)
                
                if stok_toko < stok_minimal:
                    low_products.append({
                        'produk': produk,
                        'stok_toko': stok_toko,
                        'stok_minimal': stok_minimal,
                        'qty_needed': stok_minimal - stok_toko
                    })
            
            if low_products:
                low_stock_tokos.append({
                    'toko': toko,
                    'products': low_products
                })
        
        # Send notification if any
        if low_stock_tokos:
            send_discord_dm(sator, {
                'title': f'⚠️ {len(low_stock_tokos)} toko perlu restok',
                'tokos': low_stock_tokos,
                'action_link': f'/order/quick?tokos={toko_ids}'
            })
```

### **Real-time Alert (Optional):**

```
Trigger: Promotor jual produk
→ Stok berkurang
→ If stok < minimal:
   → Send immediate alert to SATOR
   → "MTC: Y19s tinggal 1 unit (minimal 3)"
```

---

## 📱 MOBILE UI MOCKUP

### **Home - Stock Alerts:**

```
┌─────────────────────────────────────┐
│  📦 Sell-In Dashboard               │
├─────────────────────────────────────┤
│                                     │
│  ⚠️ ALERTS (3 toko)                 │
│  ┌───────────────────────────────┐ │
│  │ Transmart MTC                 │ │
│  │ 3 produk butuh restok         │ │
│  │ [Quick Order →]              │ │
│  └───────────────────────────────┘ │
│  ┌───────────────────────────────┐ │
│  │ Panakukkang                   │ │
│  │ 1 produk butuh restok         │ │
│  │ [Quick Order →]              │ │
│  └───────────────────────────────┘ │
│                                     │
│  ✅ ALL OK (12 toko)                │
│  [View All Toko]                    │
│                                     │
│  📊 Today Summary:                  │
│  Orders: 5 (Rp 85 juta)             │
│  [View Detail]                      │
│                                     │
└─────────────────────────────────────┘
```

### **Quick Order:**

```
┌─────────────────────────────────────┐
│  ← Back   📦 ORDER - MTC            │
├─────────────────────────────────────┤
│                                     │
│  🤖 AI Rekomendasi:                 │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ Y19s 8/128 Black              │ │
│  │ Stok: 1  Minimal: 3           │ │
│  │ Qty: [5] unit                 │ │
│  │ Rp 12,500,000                 │ │
│  └───────────────────────────────┘ │
│  ┌───────────────────────────────┐ │
│  │ V40 12/256 Gold               │ │
│  │ Stok: 0  Minimal: 2           │ │
│  │ Qty: [3] unit                 │ │
│  │ Rp 13,500,000                 │ │
│  └───────────────────────────────┘ │
│                                     │
│  [+ Add Product Manual]             │
│                                     │
│  Total: Rp 26,000,000 (8 unit)      │
│                                     │
│  [✏️ Edit Qty] [✅ Submit Order]    │
│                                     │
└─────────────────────────────────────┘
```

### **Success:**

```
┌─────────────────────────────────────┐
│  ✅ ORDER BERHASIL!                 │
├─────────────────────────────────────┤
│                                     │
│  Order #12345                       │
│  Toko: Transmart MTC                │
│  Total: Rp 26 juta (8 unit)         │
│                                     │
│  Status: Approved ✅                │
│  Sent to Warehouse ✅               │
│  Discord notification sent ✅       │
│                                     │
│  [View Order Detail]                │
│  [← Back to Dashboard]              │
│                                     │
└─────────────────────────────────────┘
```

---

## 🎯 KESIMPULAN

### **Current System (Complex):**

✅ **Pros:**
- Complete audit trail
- Detailed control
- Separation of concerns (rekomendasi vs order)

❌ **Cons:**
- 6 steps workflow (too long!)
- Confusing (rekomendasi vs order)
- Time consuming (30-60 min daily)
- Not mobile-friendly
- Manual detection (no auto-alert)

### **Proposed System (Simplified):**

✅ **Pros:**
- 3 steps workflow (fast!)
- Clear & simple (one action = one order)
- Time efficient (5-10 min daily)
- Mobile-first (Flutter native)
- Auto-alert (proactive)
- Auto-approve (trust SATOR)

⚠️ **Trade-offs:**
- Less granular control (but SPV can override)
- Auto-approve (need trust in SATOR)

---

## 📋 IMPLEMENTATION PRIORITY

### **Phase 1: Core (Week 1-2)**
1. ✅ Order creation (simplified)
2. ✅ Auto stock calculation
3. ✅ Submit & save to DB

### **Phase 2: Automation (Week 3)**
4. ✅ Daily cron job (stock check)
5. ✅ Discord notifications
6. ✅ Auto-approve logic

### **Phase 3: Mobile UI (Week 4)**
7. ✅ Card-based layout
8. ✅ Quick order screen
9. ✅ Swipe gestures

### **Phase 4: Advanced (Week 5-6)**
10. ✅ History & reporting
11. ✅ SPV override panel
12. ✅ Export features

---

**NEXT:** Mau saya buatkan visual mockup/wireframe untuk Flutter app? Atau review dulu proposal simplifikasi ini?
