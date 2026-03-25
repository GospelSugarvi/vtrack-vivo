# 🎯 KLARIFIKASI SISTEM - UNDERSTANDING LENGKAP

**Tanggal:** 2 Januari 2026  
**From:** Gery (SPV)  
**Purpose:** Final clarification sebelum rebuild

---

## 💡 KONSEP DASAR SISTEM

### **Ini BUKAN Aplikasi Utama Kantor!**

```
┌────────────────────────────────────────┐
│  APLIKASI RESMI KANTOR (Official)     │
│  - Sistem utama perusahaan             │
│  - Tidak lengkap untuk kebutuhan       │
│  - SPV tidak bisa kontrol penuh        │
└────────────────────────────────────────┘
              ↓
         ❌ NOT ENOUGH!
              ↓
┌────────────────────────────────────────┐
│  APLIKASI INI (Custom - by Gery)       │
│  ✅ Pencatatan tambahan                │
│  ✅ Tracking detail                    │
│  ✅ Kontrol lapangan                   │
│  ✅ Hitung bonus & achievement         │
│  ✅ Monitor real-time                  │
└────────────────────────────────────────┘
```

**Tujuan:**
> "Aplikasi ini saya buat untuk **memenuhi kebutuhan saya sebagai SPV**,  
> agar bisa **kontrol hal di lapangan** yang tidak ter-cover aplikasi resmi."

**Sifat:**
- **Shadow System** (parallel tracking)
- **Internal Use Only** (tim sendiri)
- **Supplement** (bukan replacement)
- **Real-time Monitoring Tool**

---

## 📦 SISTEM STOK (KLARIFIKASI FINAL)

### **1. Stok Otomatis Berkurang Saat Jualan ✅**

**CONFIRMED!**

```javascript
Workflow:
1. Promotor input jualan (scan IMEI)
2. System save to `jualan` table
3. System AUTO-DECREMENT dari stok
   - Delete from `stok` table? OR
   - Mark as sold? OR
   - Update counter?

Action Needed: Lihat code untuk confirm exact logic
```

**Benefit:**
- Always accurate inventory
- No manual adjustment
- Prevent overselling

---

### **2. Stok Gudang = Landasan untuk Order**

**Role: SATOR**

```
┌────────────────────────────────────────┐
│  STOK GUDANG KANTOR PUSAT              │
│  Input by: SATOR (daily)               │
│  Purpose: Reference untuk push order   │
├────────────────────────────────────────┤
│                                        │
│  Y19s 8/128: 100 unit (gudang)         │
│  V40 12/256: 50 unit (gudang)          │
│  Y400 6/128: 200 unit (gudang)         │
│                                        │
└────────────────────────────────────────┘
              ↓
      SATOR Decision:
      "Toko MTC perlu 15 unit Y19s"
              ↓
      Push Order ke Toko
              ↓
┌────────────────────────────────────────┐
│  ORDER                                 │
│  Dari: Gudang Pusat                    │
│  Ke: Transmart MTC                     │
│  Item: Y19s 8/128 = 15 unit            │
│  Status: Pending approval              │
└────────────────────────────────────────┘
```

**Koordinasi:**
```
SATOR ↔ Gudang: "Ada berapa stok Y19s?"
SATOR ↔ Toko:   "Butuh berapa unit?"
SATOR: Create order 
       → Submit ke sistem
       → Approval flow
       → Kirim barang
```

---

### **3. Stok Display = ABAIKAN ❌**

**CONFIRMED: Tidak perlu tracking!**

```
OLD System:
- Stok Display (demo unit)
- Stok Ready (jual)
- Stok Transit
- Stok Chip

NEW System (Simplified):
✅ Stok Ready (Fresh - siap jual)
✅ Stok Chip (Special - untuk kejar target)
❌ Stok Display (SKIP!)
❌ Stok Transit (SKIP!)
```

**Alasan:**
- Display = terlalu detail, tidak penting
- Transit = temporary status, tidak perlu track
- Focus: Yang bisa DIJUAL aja!

---

### **4. Fresh/Ready Stok vs Chip Stok**

#### **A. Stok Fresh/Ready (Normal Flow)**

```
Source: Gudang Kantor
Status: Fresh, Sealed, Brand New
Flow:
1. SATOR koordinasi → Push order
2. Gudang kirim ke toko
3. Promotor terima barang
4. Promotor scan IMEI → Input ke sistem
5. Stok ready untuk dijual

Tipe: NORMAL
Approval: Automatic (standard flow)
```

#### **B. Stok Chip (Special - Untuk Kejar Target)**

```
Source: ???
Status: Second? Ex-display? Return?
Flow:
1. Promotor identify stok chip
2. Promotor REQUEST aktivasi
3. SEMUA PIHAK approve:
   - SATOR: OK ✅
   - SPV: OK ✅
   - (Manager?: OK ✅)
4. After approval → Activate
5. Promotor input ke sistem
6. Bisa dijual untuk kejar target

Tipe: TIDAK NORMAL (emergency measure)
Approval: WAJIB dari semua pihak!
Purpose: Achieve monthly target
```

**Pertanyaan Klarifikasi:**

1. **Stok Chip dari mana?**
   - Ex-display unit?
   - Return customer?
   - Damaged/repaired?
   - Dari cabang lain?

2. **Kenapa perlu approval?**
   - Harga lebih murah?
   - Quality berbeda?
   - Accounting issue?
   - Against policy?

3. **Approval flow:**
   - Promotor request via app?
   - SATOR approve via app?
   - SPV final approve?
   - Atau offline (voice/chat)?

4. **Price different?**
   - Chip = harga lebih murah?
   - Bonus calculation sama/beda?

---

### **5. Tugas & Responsibility**

#### **PROMOTOR:**

```
✅ Input Stok Masuk (ke sistem)
   - Scan IMEI
   - Catat di database
   - Track individual unit

✅ Input Penjualan
   - Scan IMEI yang dijual
   - System auto-decrement stok

✅ Request Stok Chip (kalau perlu)
   - Submit approval request
   - Tunggu approval
   - Activate setelah approved

Purpose: RECORDING detailed inventory
```

#### **SATOR:**

```
✅ Koordinasi Gudang ↔ Toko
   - Cek stok gudang available
   - Tanya toko butuh apa
   - Decide qty order

✅ Push Order
   - Create order ke toko
   - Submit untuk approval
   - Track delivery

✅ Input Stok Gudang Daily
   - Update aggregate count
   - Reference untuk decision

✅ Approve Stok Chip Request
   - Review legitimacy
   - Approve/Reject

Purpose: COORDINATION & DECISION MAKING
```

#### **SPV (Gery):**

```
✅ Monitor Semua Aktivitas
   - Lihat all toko performance
   - Track all orders
   - Monitor stok levels

✅ Final Approval
   - Approve orders
   - Approve chip activation
   - Override decisions

✅ Generate Reports
   - Export data
   - Analyze trends
   - Share to management

Purpose: CONTROL & OVERSIGHT
```

---

## 🎯 SISTEM INI = PENCATATAN & TRACKING

### **Bukan ERP, Tapi Control Panel!**

```
Aplikasi Resmi Kantor:
├─ Inventory Management (basic)
├─ Sales Recording (basic)
├─ Order Processing (basic)
└─ Reporting (limited)

Aplikasi Ini (Custom):
├─ ✅ Detail Tracking (IMEI level)
├─ ✅ Real-time Monitoring
├─ ✅ Bonus Calculation (dynamic rules)
├─ ✅ Target Achievement Progress
├─ ✅ Team Performance Comparison
├─ ✅ Alert System (low stock, underperform)
├─ ✅ Daily Activity Checklist
├─ ✅ VAST Finance Tracking
├─ ✅ Social Media Promotion Tracking
├─ ✅ Competitor Analysis (AllBrand)
└─ ✅ Custom Reports untuk SPV

= SUPERSET of official system!
```

### **Key Difference:**

| Feature | Official App | Custom App (This) |
|---------|--------------|-------------------|
| **User** | Seluruh perusahaan | Tim internal (Gery's team) |
| **Purpose** | Operational | Monitoring & Control |
| **Scope** | Generic | Specific to SPV needs |
| **Flexibility** | Rigid | Customizable |
| **Detail Level** | Summary | Granular (IMEI, daily) |
| **Bonus Calc** | Manual? | Auto with rules |
| **Real-time** | No | Yes |
| **Alerts** | No | Yes |
| **Custom Reports** | Limited | Unlimited |

---

## 🔄 TYPICAL WORKFLOW

### **Daily Morning (Standard Flow):**

```
07:00 - Promotor Clock In
       → Selfie + GPS
       → System track attendance

08:00 - Barang Datang ke Toko (from Gudang)
       → Promotor cek fisik
       → Scan IMEI satu-satu
       → Input ke sistem
       → Stok bertambah ✅

09:00 - SATOR Input Stok Gudang
       → Upload screenshot atau manual
       → System parse & save
       → Reference untuk order decision

10:00 - SATOR Review Toko Stock Levels
       → Dashboard: Toko mana yang low stock?
       → Koordinasi dengan gudang
       → Create order untuk restocking
```

### **During Day (Sales Activity):**

```
11:00 - Customer datang ke toko
       → Promotor show product
       → Customer beli Y19s

11:15 - Promotor Input Penjualan
       → Scan IMEI produk yang dibeli
       → Input detail (harga, payment, dll)
       → System:
          - Save to `jualan` ✅
          - Delete from `stok` ✅ (auto-decrement!)
          - Calculate bonus ✅
          - Send notification Discord ✅

11:30 - SATOR lihat notification Discord
       → "Ahmad sold 1 unit Y19s"
       → Check dashboard progress
       → Monitor team achievement
```

### **Special Case (Kejar Target - Chip Activation):**

```
26 Jan - End of Month Approaching
       → Ahmad masih kurang 3 unit untuk target
       → Toko ada 2 unit chip (ex-display)

       Ahmad Request:
       "Minta aktivasi 2 unit chip untuk kejar target"
       
       ↓
       
       SATOR Review:
       - Cek legitimacy
       - Cek apakah reasonable
       - Approve atau reject
       
       ↓
       
       SPV Final Approve:
       - Gery lihat request
       - Consider situation
       - Final decision
       
       ↓
       
       IF APPROVED:
       - Ahmad scan IMEI chip unit
       - Input dengan flag "chip"
       - System track separately
       - Bisa dijual dengan price discount
       - Counted toward target ✅
```

---

## 📊 DASHBOARD FOCUS

### **SPV Dashboard (Gery) - Main Control Panel:**

```
┌────────────────────────────────────────┐
│  📊 MASTER DASHBOARD                   │
├────────────────────────────────────────┤
│                                        │
│  Today's Summary:                      │
│  - Total Sales: 45 unit (Rp 125jt)     │
│  - Achievement: 87% (target 90%)       │
│  - Attendance: 33/35 promotor          │
│  - Pending Approvals: 3 orders         │
│                                        │
│  🔴 ALERTS (5):                        │
│  - Toko MTC: Stok Y19s low (2 unit)    │
│  - Ahmad: Belum clock in               │
│  - Order #123: Pending approval        │
│  - Budi: Target only 45% (⚠️ critical) │
│  - Chip request: Waiting your approval │
│                                        │
│  Quick Actions:                        │
│  [Approve Orders] [View Team]          │
│  [Generate Report] [Settings]          │
│                                        │
└────────────────────────────────────────┘
```

**Purpose:**
- At-a-glance overview
- Quick decision making
- Immediate action on alerts
- Control everything from one place

---

## ✅ KESIMPULAN & NEXT STEPS

### **Pemahaman Final:**

1. ✅ **Stok auto-decrement** saat jualan
2. ✅ **Stok Gudang** = reference untuk SATOR push order
3. ✅ **Skip Display tracking** (tidak penting)
4. ✅ **Fresh/Ready** = normal flow
5. ✅ **Chip** = special (need approval) untuk kejar target
6. ✅ **Promotor** = input recorder
7. ✅ **SATOR** = coordinator
8. ✅ **Sistem ini** = pencatatan & kontrol tambahan (bukan replacement official app)

### **Implications untuk Design:**

**Database:**
```sql
-- Simplified stock table
CREATE TABLE stok (
  id BIGSERIAL PRIMARY KEY,
  produk_id BIGINT REFERENCES produk(id),
  promotor_id BIGINT REFERENCES users(id),
  toko_id BIGINT REFERENCES toko(id),
  imei VARCHAR(255) UNIQUE NOT NULL,
  tipe_stok VARCHAR(20) NOT NULL,  -- 'fresh' or 'chip'
  status VARCHAR(20) DEFAULT 'active',  -- 'active', 'sold', 'damaged'
  created_at TIMESTAMP DEFAULT NOW(),
  sold_at TIMESTAMP NULL,
  chip_approved_by BIGINT NULL REFERENCES users(id),
  chip_approved_at TIMESTAMP NULL
);

-- Fresh: Standard flow, no approval needed
-- Chip: Requires approval, tracked separately
```

**UI Simplification:**
```
Promotor Input Stok:
┌────────────────────────────┐
│ Scan IMEI: [___________]   │
│                            │
│ Tipe:                      │
│ ⦿ Fresh (Normal)           │
│ ○ Chip (Perlu Approval)    │
│                            │
│ [Submit]                   │
└────────────────────────────┘

If Chip selected:
→ Submit approval request
→ Notify SATOR + SPV
→ Wait approval
→ After approved → activate
```

**Approval Flow:**
```
Chip Request → SATOR Review → SPV Final Approval → Activate
```

---

## 🤔 FINAL QUESTIONS (Opsional):

1. **Official app integration?**
   - Apakah data dari official app di-sync ke app ini?
   - Atau completely separate?
   
2. **Chip pricing:**
   - Harga jual chip = lebih murah dari fresh?
   - Bonus calculation berbeda?
   
3. **Report to management:**
   - Export dari app ini → kirim ke Manager Area?
   - Atau Manager Area tidak gunakan app ini?

4. **Data retention:**
   - Historical data disimpan berapa lama?
   - Archive strategy?

**Tapi ini bisa later! Yang penting sekarang:**
- ✅ Core understanding sudah clear
- ✅ System purpose sudah jelas
- ✅ User roles sudah defined
- ✅ Workflows sudah mapped

**Ready untuk design & build!** 🚀
