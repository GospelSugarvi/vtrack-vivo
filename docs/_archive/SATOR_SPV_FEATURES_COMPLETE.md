# 📋 ANALISIS LENGKAP: FITUR & KEBUTUHAN SATOR/SPV/LEADER

**Berdasarkan:** Sistem yang sudah ada (Django)  
**Tujuan:** Dokumentasi untuk rebuild Flutter app  
**Tanggal:** 2 Januari 2026

---

## 🎯 OVERVIEW: APA YANG SATOR/SPV LAKUKAN?

**SATOR/SPV/Leader** adalah **supervisor/manager** yang bertugas:
1. **Monitor** semua aktivitas promotor bawahan
2. **Approve/Reject** order dari toko
3. **Set target** bulanan untuk promotor
4. **Manage tim** (tambah, hapus, pindah toko)
5. **Analisis performa** tim dan toko
6. **Report** ke atasan (SPV/Manager Area)

**Total User:** 
- SATOR: 2 orang
- SPV: 1 orang
- (Manager Area: TIDAK MASUK SISTEM INTERNAL INI)

---

## 📊 HIERARCHY & PERMISSION

```
┌─────────────┐
│    SPV      │ (1 orang)
└──────┬──────┘
       │ View & manage all SATOR
       │
   ┌───┴────┐
   ▼        ▼
┌────────┐ ┌────────┐
│SATOR 1 │ │SATOR 2 │ (2 orang)
└───┬────┘ └───┬────┘
    │           │ View & manage own promotors
    ▼           ▼
[Promotor]  [Promotor] (±17-18 each)
```

**Permission Differences:**
- **SPV:** View ALL data, approve ALL orders, manage ALL teams
- **SATOR:** View OWN TEAM only, approve OWN orders, manage OWN promotors

---

## 📱 YANG SATOR/SPV BUTUHKAN DARI PROMOTOR

### **1. DAILY ACTIVITIES (Harian)**

**Yang harus promotor laporkan:**
```
✅ Absensi (Clock in)
   - Selfie + GPS
   - Jam berapa masuk
   
💰 Penjualan (Jualan)
   - Berapa unit terjual
   - Omzet berapa
   - IMEI produk apa
   - Bonus earned
   
📦 Update Stok
   - Stok masuk
   - Stok kosong
   - Display vs Ready

📣 Promosi Medsos
   - Platform apa (TikTok, IG, FB)
   - Berapa post
   - Screenshot bukti

💳 Pengajuan VAST
   - Customer data
   - Produk apa
   - Status: Pending/Approved/Rejected
```

### **2. TEAM PERFORMANCE DATA (Real-time)**

**Yang SATOR/SPV dapatkan:**
```
Dashboard Summary:
- Total sales per promotor (hari ini)
- Achievement vs target (%)
- Total omzet tim
- Top performer (ranking)
- Bottom performer (perlu follow-up)
- Promotor belum clock in (alert!)
- Promotor belum input (alert!)
```

---

## 📱 HALAMAN & FITUR SATOR/SPV

### **1. DASHBOARD MONITORING** ⭐ CORE
**File:** `monitoring_views.py`  
**URL:** `/sales/api/monitoring/dashboard/`

#### **Main View:**

```
┌─────────────────────────────────────────┐
│  📊 DASHBOARD MONITORING                │
├─────────────────────────────────────────┤
│                                         │
│  Filter: [Hari Ini ▼]  Area: [NIO ▼]   │
│                                         │
│  ┌───────────┬───────────┬───────────┐ │
│  │ 📍 Toko   │ 👤 Promo  │ 🎯 Status │ │
│  ├───────────┼───────────┼───────────┤ │
│  │Transmart  │  Ahmad    │ ✅✅✅✅ │ │
│  │MTC        │           │  4/4      │ │
│  │           │           │           │ │
│  │           │  Budi     │ ✅✅❌⚠️ │ │
│  │           │           │  2/4      │ │
│  ├───────────┼───────────┼───────────┤ │
│  │Panakkukang│  Cici     │ ❌❌❌❌ │ │
│  │           │           │  0/4      │ │
│  └───────────┴───────────┴───────────┘ │
│                                         │
│  Legend:                                │
│  ✅ Absen ✅ Jualan ✅ Stok ✅ Promosi │
│                                         │
│  [View All Details] [Send Follow-up]   │
│                                         │
└─────────────────────────────────────────┘
```

#### **Checklist Status (Per Promotor Harian):**

```
Checklist Item:
☑ Absensi (clock in)
☑ Laporan Jualan (minimal 1 penjualan)
☑ Update Stok (minimal 1 update)
☑ Promosi Medsos (minimal 1 platform)

Color Codes:
🟢 4/4 = Excellent (semua done)
🟡 2-3/4 = Needs improvement
🔴 0-1/4 = Critical (perlu follow-up!)
```

#### **Detail View per Toko:**

```
┌─────────────────────────────────────────┐
│  📍 Transmart MTC - Detail              │
├─────────────────────────────────────────┤
│                                         │
│  Promotor: Ahmad                        │
│  Status: ✅ Complete (4/4)              │
│                                         │
│  ✅ Absensi: 08:00 WITA                │
│      📸 [Lihat Foto] 📍 [Lihat Map]    │
│                                         │
│  ✅ Sell Out: 5 unit (Rp 12.5jt)       │
│      [Detail Penjualan ▼]              │
│      - Y19s 8/128: 2 unit              │
│      - V40 12/256: 3 unit              │
│                                         │
│  ✅ Stok: 3 item updated               │
│      [Detail Stok ▼]                   │
│      - Display: +2 unit                │
│      - Ready: +1 unit                  │
│                                         │
│  ✅ Promosi: 2 platform                │
│      [Detail Promosi ▼]                │
│      - TikTok: 3 foto                  │
│      - Instagram: 2 foto               │
│                                         │
│  💳 VAST: 1 pengajuan (Pending)        │
│      [View Detail]                     │
│                                         │
│  Actions:                               │
│  [👍 Give Kudos] [💬 Send Message]     │
│                                         │
└─────────────────────────────────────────┘
```

#### **Follow-up Feature:**

**Use case:** Promotor belum aktivitas → SATOR kirim reminder

```
[Send Follow-up Modal]

To: Ahmad (Transmart MTC)
Template: [Belum Absen ▼]

Message Preview:
"Halo Ahmad, hari ini belum clock in ya.
Jangan lupa absen dan update aktivitas.
Semangat! 💪"

Channel: 
☑ Discord DM
☐ WhatsApp

[Send] [Cancel]
```

**Backend:** `followup_promotor_api()`

---

### **2. DASHBOARD SELLOUT (Performance)** ⭐ CORE
**File:** `dashboard_sellout_v2_views.py`  
**URL:** `/sales/dashboard/sellout/`

#### **Main View:**

```
┌─────────────────────────────────────────┐
│  📊 DASHBOARD SELLOUT                   │
├─────────────────────────────────────────┤
│                                         │
│  Period: [Bulan Ini ▼]  Toko: [All ▼]  │
│                                         │
│  📈 SUMMARY                             │
│  ┌───────────┬───────────┬───────────┐ │
│  │ Omzet     │ Unit      │ Achievement│ │
│  │ 125 juta  │  78 unit  │    78%    │ │
│  └───────────┴───────────┴───────────┘ │
│                                         │
│  📊 WEEKLY BREAKDOWN                    │
│  ┌─────┬─────┬─────┬─────┐            │
│  │Week │Unit │Omzet│ Tgt │            │
│  ├─────┼─────┼─────┼─────┤            │
│  │  1  │ 15  │ 25M │ 75% │            │
│  │  2  │ 22  │ 35M │ 88% │            │
│  │  3  │ 18  │ 30M │ 72% │            │
│  │  4  │ 23  │ 35M │ 92% │            │
│  └─────┴─────┴─────┴─────┘            │
│                                         │
│  🎯 FOKUS PRODUCTS                      │
│  ┌─────────────────────────────────┐   │
│  │ Y19s: 25 unit (Target: 30)      │   │
│  │ V40: 15 unit (Target: 20)       │   │
│  │ Y400: 10 unit (Target: 15)      │   │
│  └─────────────────────────────────┘   │
│                                         │
│  👥 TOP PERFORMERS                      │
│  ┌─────────────────────────────────┐   │
│  │ 🥇 Ahmad: 23 unit (92% target)  │   │
│  │ 🥈 Budi: 18 unit (72% target)   │   │
│  │ 🥉 Cici: 15 unit (60% target)   │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ⚠️ UNDERPERFORMERS                     │
│  ┌─────────────────────────────────┐   │
│  │ ⚠️ Dedi: 5 unit (20% target)    │   │
│  │ ⚠️ Eka: 8 unit (32% target)     │   │
│  └─────────────────────────────────┘   │
│                                         │
│  📊 MARKET SHARE (All Brands)           │
│  ┌─────────────────────────────────┐   │
│  │ VIVO: 35% (78 unit)             │   │
│  │ Samsung: 30% (67 unit)          │   │
│  │ OPPO: 20% (45 unit)             │   │
│  │ Realme: 10% (22 unit)           │   │
│  │ Xiaomi: 5% (11 unit)            │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Actions:                               │
│  [📤 Export Excel] [📸 Export Image]   │
│  [📢 Send to Discord]                   │
│                                         │
└─────────────────────────────────────────┘
```

#### **Export Features:**

**1. Export Excel:**
- Summary data
- Weekly breakdown
- Per promotor detail
- Fokus products
- Market share comparison

**2. Export Image (for Discord):**
- Visual card design
- Graphs & charts
- Auto-send to team channel

**3. Send to Discord:**
- Auto-formatted message
- Tag team members
- Include image preview

---

### **3. SET TARGET PROMOTOR** ⭐ MANAGEMENT
**File:** `target_promotor_views.py`  
**URL:** `/sales/api/target-promotor/`

#### **Target Input Screen:**

```
┌─────────────────────────────────────────┐
│  🎯 SET TARGET - Januari 2026           │
├─────────────────────────────────────────┤
│                                         │
│  Team: TIM NIO (SATOR: NIO)             │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ Promotor: Ahmad                 │   │
│  │ Toko: Transmart MTC             │   │
│  │                                 │   │
│  │ Target Omzet:                   │   │
│  │ Rp [50,000,000]                 │   │
│  │                                 │   │
│  │ Target Unit Fokus:              │   │
│  │ [20] unit                       │   │
│  │                                 │   │
│  │ Target Y400 Series:             │   │
│  │ [5] unit                        │   │
│  │                                 │   │
│  │ Target Y29 Series:              │   │
│  │ [8] unit                        │   │
│  │                                 │   │
│  │ Target V Series:                │   │
│  │ [7] unit                        │   │
│  │                                 │   │
│  │ Target VAST Finance:            │   │
│  │ [10] aplikasi                   │   │
│  │                                 │   │
│  │ Target TikTok Followers:        │   │
│  │ [50] follower                   │   │
│  │                                 │   │
│  │ Target Promosi Post:            │   │
│  │ [30] post                       │   │
│  │                                 │   │
│  │ [Save] [Cancel]                 │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Quick Actions:                         │
│  [Copy from Last Month]                 │
│  [Apply to All Promotor]                │
│  [Set Team Target (Distribute Auto)]   │
│                                         │
│  ────────────────────────────────────  │
│                                         │
│  📋 All Promotors (17 total)            │
│  ┌─────────────────────────────────┐   │
│  │ ✅ Ahmad - Set (50M, 20 unit)   │   │
│  │ ✅ Budi - Set (45M, 18 unit)    │   │
│  │ ⚪ Cici - Not set yet           │   │
│  │ ⚪ Dedi - Not set yet           │   │
│  │ ...                             │   │
│  └─────────────────────────────────┘   │
│                                         │
│  [Save All Targets]                     │
│                                         │
└─────────────────────────────────────────┘
```

#### **API Endpoints:**

**1. Get Targets:**
```javascript
GET /api/target-promotor/list/?month=12&year=2025

Response:
{
  "status": "success",
  "data": [
    {
      "promotor_id": 1,
      "nama": "Ahmad",
      "toko": "Transmart MTC",
      "target": {
        "target_omzet_rp": 50000000,
        "target_total_unit_fokus": 20,
        "target_unit_y400_series": 5,
        ...
      }
    },
    ...
  ]
}
```

**2. Save Single Target:**
```javascript
POST /api/target-promotor/save/
Body: {
  "promotor_id": 1,
  "month": 12,
  "year": 2025,
  "target_omzet_rp": 50000000,
  "target_total_unit_fokus": 20,
  ...
}
```

**3. Bulk Save (Recommended):**
```javascript
POST /api/target-promotor/save-all/
Body: {
  "month": 12,
  "year": 2025,
  "targets": [
    { "promotor_id": 1, "target_omzet_rp": 50000000, ... },
    { "promotor_id": 2, "target_omzet_rp": 45000000, ... },
    ...
  ]
}
```

---

### **4. KELOLA TIM (Team Management)** ⭐ MANAGEMENT
**File:** `kelola_tim_views.py`  
**URL:** `/sales/api/kelola-tim/`

#### **Team List View:**

```
┌─────────────────────────────────────────┐
│  👥 KELOLA TIM - TIM NIO                │
├─────────────────────────────────────────┤
│                                         │
│  [+ Tambah Promotor]  Search: [____]🔍 │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ Ahmad                           │   │
│  │ Transmart MTC · Official        │   │
│  │ Discord: @ahmad123              │   │
│  │ Status: Aktif                   │   │
│  │                                 │   │
│  │ [Edit] [Pindah Toko] [Hapus]   │   │
│  ├─────────────────────────────────┤   │
│  │ Budi                            │   │
│  │ Panakukkang · Training          │   │
│  │ Discord: @budi456               │   │
│  │ Status: Aktif                   │   │
│  │                                 │   │
│  │ [Edit] [Pindah Toko] [Hapus]   │   │
│  ├─────────────────────────────────┤   │
│  │ Cici (Inactive)                 │   │
│  │ Mall Ratu · Official            │   │
│  │ Status: Non-Aktif               │   │
│  │                                 │   │
│  │ [Activate] [Edit] [Hapus]       │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Total: 17 promotor (16 aktif)          │
│                                         │
└─────────────────────────────────────────┘
```

#### **Actions:**

**1. Tambah Promotor:**
```
[Form Modal]

Nama Lengkap: [Ahmad Promotor]
Nama Panggilan: [Ahmad]
Discord User ID: [123456789]
  (Get from Discord bio)

Status: ⦿ Official  ○ Training

Toko: [Transmart MTC ▼]

[Save] [Cancel]
```

**2. Edit Promotor:**
```
[Edit Modal - Same fields as Tambah]

Can update:
- Nama
- Discord ID
- Status (Official/Training)
- Toko assignment
```

**3. Pindah Toko (Rotasi):**
```
[Pindah Toko Modal]

Promotor: Ahmad
Toko Sekarang: Transmart MTC

Pindah ke: [Panakukkang ▼]

Alasan rotasi: [____________]

[Confirm] [Cancel]
```

**4. Hapus Promotor:**
```
[Confirm Modal]

⚠️ Yakin hapus Ahmad dari tim?

Data penjualan akan tetap tersimpan,
tapi Ahmad tidak lagi di bawah Anda.

[Yes, Hapus] [Cancel]
```

#### **API Endpoints:**

**List Tim:**
```javascript
GET /api/kelola-tim/list/
```

**Tambah:**
```javascript
POST /api/kelola-tim/tambah/
Body: {
  "nama_lengkap": "Ahmad Promotor",
  "nama_panggilan": "Ahmad",
  "discord_user_id": "123456789",
  "status": "official", // or "training"
  "toko_id": 1
}
```

**Edit:**
```javascript
POST /api/kelola-tim/edit/
Body: {
  "promotor_id": 1,
  "nama_lengkap": "Ahmad Baru",
  ...
}
```

**Pindah Toko:**
```javascript
POST /api/kelola-tim/pindah-toko/
Body: {
  "promotor_id": 1,
  "toko_id": 2
}
```

**Hapus:**
```javascript
POST /api/kelola-tim/hapus/
Body: {
  "promotor_id": 1
}
```

**Ubah Status:**
```javascript
POST /api/kelola-tim/ubah-status/
Body: {
  "promotor_id": 1,
  "status": "training" // or "official"
}
```

---

### **5. SELL IN (Order Approval)** ⭐ OPERATIONS
**File:** `sell_in_views.py`  
**URL:** `/sales/sell-in/`

#### **Verifikasi Order Screen:**

```
┌─────────────────────────────────────────┐
│  📦 VERIFIKASI ORDER - 2 Jan 2026       │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────┬──────────┬──────────┐    │
│  │ Pending  │ Approved │ Rejected │    │
│  │    5     │     3    │     1    │    │
│  └──────────┴──────────┴──────────┘    │
│                                         │
│  Pending Orders (5):                    │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ Order #001                      │   │
│  │ Toko: Transmart MTC             │   │
│  │ Sales: Ahmad                    │   │
│  │ Total: Rp 25,000,000 (15 prod)  │   │
│  │ Submit: 08:30                   │   │
│  │                                 │   │
│  │ [View Detail ▼]                 │   │
│  │                                 │   │
│  │ Items:                          │   │
│  │ - Y19s 8/128: 5 unit × 2.5M     │   │
│  │ - V40 12/256: 3 unit × 4.5M     │   │
│  │ - Y400 6/128: 7 unit × 2.2M     │   │
│  │                                 │   │
│  │ [✅ Approve] [❌ Reject]        │   │
│  ├─────────────────────────────────┤   │
│  │ Order #002                      │   │
│  │ ...                             │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Actions:                               │
│  [✅ Approve All] [📋 No Orders Today] │
│  [📤 Send Daily Report to Discord]     │
│                                         │
└─────────────────────────────────────────┘
```

#### **Workflow:**

**Daily Flow:**
```
1. Sales/Promotor submit order (via form)
   → Status: "submitted"

2. SATOR review di Verifikasi page
   → View detail items
   → Check stock availability
   
3. SATOR decision:
   ✅ Approve → Status: "approved"
   ❌ Reject → Status: "rejected"

4. End of day:
   [Send Daily Report] button
   → Generate summary
   → Send to Discord channel
   → Notify warehouse team
```

**Report Format (Discord):**
```
📦 DAILY SELL IN REPORT
📅 2 Januari 2026
👤 SATOR: NIO

✅ APPROVED (3 orders):
1. Transmart MTC - Rp 25M (15 prod)
2. Panakukkang - Rp 18M (10 prod)
3. Mall Ratu - Rp 12M (8 prod)

Total Approved: Rp 55 juta (33 produk)

❌ REJECTED (1 order):
- Plaza XYZ - Stock tidak tersedia

⚠️ Action Required:
Warehouse: Prepare 33 units for delivery
```

#### **History View:**

```
┌─────────────────────────────────────────┐
│  📜 HISTORY ORDER                       │
├─────────────────────────────────────────┤
│                                         │
│  Filter:                                │
│  From: [01/01/2026]  To: [31/01/2026]   │
│  Status: [Approved ▼]                   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ Date     │ Toko  │ Total │ Stat │   │
│  ├──────────┼───────┼───────┼──────┤   │
│  │ 2/1/2026 │ MTC   │ 25M   │  ✅  │   │
│  │ 1/1/2026 │ Panak │ 18M   │  ✅  │   │
│  │ 31/12/25 │ Ratu  │ 12M   │  ❌  │   │
│  └──────────┴───────┴───────┴──────┘   │
│                                         │
│  [📤 Export Excel] [📄 Export PDF]     │
│                                         │
└─────────────────────────────────────────┘
```

---

### **6. DASHBOARD VAST FINANCE**
**File:** `dashboard_vast_views.py`  
**URL:** `/sales/dashboard/vast/leader/`

#### **VAST Summary (for SATOR/SPV):**

```
┌─────────────────────────────────────────┐
│  💳 VAST FINANCE - Team Performance     │
├─────────────────────────────────────────┤
│                                         │
│  Period: [Bulan Ini ▼]                  │
│                                         │
│  📊 OVERALL STATS                       │
│  ┌─────────────────────────────────┐   │
│  │ Total: 45 aplikasi              │   │
│  │ Approved: 28 (62%)              │   │
│  │ Rejected: 10 (22%)              │   │
│  │ Pending: 7 (16%)                │   │
│  │                                 │   │
│  │ Target: 50 aplikasi             │   │
│  │ Achievement: 90% 🎯             │   │
│  └─────────────────────────────────┘   │
│                                         │
│  👥 PER PROMOTOR                        │
│  ┌─────────────────────────────────┐   │
│  │ Ahmad: 12 (10 ✅, 2 ❌)         │   │
│  │ Approval rate: 83%              │   │
│  │ [View Details]                  │   │
│  ├─────────────────────────────────┤   │
│  │ Budi: 8 (5 ✅, 2 ❌, 1 ⏳)      │   │
│  │ Approval rate: 62%              │   │
│  │ [View Details]                  │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ⏳ PENDING APPROVALS (7)               │
│  ┌─────────────────────────────────┐   │
│  │ Customer: Budi Santoso          │   │
│  │ Promotor: Ahmad                 │   │
│  │ Produk: Y19s 8/128              │   │
│  │ Penghasilan: Rp 5jt/bln         │   │
│  │ Submit: 1 jam lalu              │   │
│  │                                 │   │
│  │ [Update Status ▼]               │   │
│  │   ✅ Approve                    │   │
│  │   ❌ Reject                     │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Actions:                               │
│  [📤 Export Excel] [📸 Export Image]   │
│  [📢 Send to Discord]                   │
│                                         │
└─────────────────────────────────────────┘
```

**Use Case:**
- Monitor team VAST performance
- Update pending status (Approved/Rejected)
- Track approval rate per promotor
- Export for reporting

---

### **7. STOK GUDANG MANAGEMENT**
**File:** `stok_gudang_views.py`, `stok_ready_views.py`  
**URL:** `/sales/dashboard/create-stok-gudang/`

#### **Input Stok Gudang:**

```
┌─────────────────────────────────────────┐
│  📦 INPUT STOK GUDANG HARIAN            │
├─────────────────────────────────────────┤
│                                         │
│  Tanggal: [2 Januari 2026]              │
│                                         │
│  Method 1: Upload Screenshot            │
│  ┌─────────────────────────────────┐   │
│  │                                 │   │
│  │  📷 Drop image here             │   │
│  │  or click to upload             │   │
│  │                                 │   │
│  │  AI will auto-detect products   │   │
│  │  and quantities                 │   │
│  │                                 │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Method 2: Manual Input                 │
│  ┌─────────────────────────────────┐   │
│  │ Produk          │ Gudang │ OTW │   │
│  ├─────────────────┼────────┼─────┤   │
│  │ Y19s 8/128 Blk  │  [15]  │ [5] │   │
│  │ V40 12/256 Gold │  [8]   │ [0] │   │
│  │ Y400 6/128 Blk  │  [3]   │ [10]│   │
│  │ [+ Add Product]              │   │
│  └─────────────────────────────────┘   │
│                                         │
│  [Preview] [Save to Database]           │
│  [Send to Discord]                      │
│                                         │
└─────────────────────────────────────────┘
```

#### **Stok Ready per Toko:**

```
┌─────────────────────────────────────────┐
│  📦 STOK READY - All Toko               │
├─────────────────────────────────────────┤
│                                         │
│  Filter: [Series: All ▼]  [Search]      │
│                                         │
│  🏪 Transmart MTC                       │
│  ┌─────────────────────────────────┐   │
│  │ Y19s 8/128: 5 ✅ (Cukup)        │   │
│  │ V40 12/256: 2 ⚠️ (Tipis)        │   │
│  │ Y400 6/128: 0 ❌ (Kosong)       │   │
│  └─────────────────────────────────┘   │
│                                         │
│  🏪 Panakukkang                         │
│  ┌─────────────────────────────────┐   │
│  │ Y19s 8/128: 12 ✅               │   │
│  │ V40 12/256: 8 ✅                │   │
│  │ Y400 6/128: 1 ⚠️                │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ⚠️ CRITICAL ALERTS (3)                 │
│  - MTC: Y400 kosong (perlu restock!)   │
│  - Ratu: V40 tipis (hanya 2 unit)      │
│  - Plaza: Y19s kosong                   │
│                                         │
│  [📤 Send Restocking Alert]             │
│                                         │
└─────────────────────────────────────────┘
```

---

### **8. REKOMENDASI ORDER**
**File:** `rekomendasi_order_views.py`, `form_order_views.py`

#### **Auto-generated Recommendations:**

```
┌─────────────────────────────────────────┐
│  🤖 REKOMENDASI ORDER OTOMATIS          │
├─────────────────────────────────────────┤
│                                         │
│  Berdasarkan:                           │
│  - Sales velocity (7 hari terakhir)     │
│  - Current stock level                  │
│  - Target achievement                   │
│                                         │
│  🏪 Transmart MTC                       │
│  ┌─────────────────────────────────┐   │
│  │ Produk     │Stock│Rec │ Reason │   │
│  ├────────────┼─────┼────┼────────┤   │
│  │ Y19s 8/128 │ 2   │ 10 │ 🔥Fast │   │
│  │ V40 12/256 │ 0   │ 5  │ ❌Empty│   │
│  │ Y400 6/128 │ 8   │ 0  │ ✅OK   │   │
│  └─────────────────────────────────┘   │
│                                         │
│  Total Order: Rp 48,500,000 (15 unit)   │
│                                         │
│  [✏️ Edit] [✅ Approve] [📤 Submit]     │
│                                         │
└─────────────────────────────────────────┘
```

**Logic:**
```javascript
Rekomendasi Qty = 
  (Daily Sales Average × 7 days) 
  - Current Stock 
  + Safety Buffer (2 units)

Example:
Y19s:
- Daily avg: 2 unit/day
- Forecast 7 days: 14 unit
- Current stock: 2 unit
- Need: 14 - 2 = 12 unit
- With buffer: 12 + 2 = 14 unit
- Recommend: Order 14 unit
```

---

## 📊 YANG SATOR/SPV BUTUHKAN (SUMMARY)

### **Data dari Promotor (Daily):**

```
✅ Checklist Items:
1. Absensi (photo + GPS + time)
2. Penjualan (IMEI + produk + harga + customer)
3. Stok update (tipe + qty + foto)
4. Promosi (platform + screenshot)
5. VAST (customer data + KTP)
6. Follower TikTok (username + screenshot)
7. Laporan Allbrand (competitor count)
```

### **Dashboard/Reports (Real-time):**

```
📊 Performance Metrics:
- Total sales (unit & omzet)
- Achievement vs target (%)
- Weekly breakdown
- Top/bottom performers
- Market share vs competitor

📈 Trends & Insights:
- Sales velocity
- Focus product performance
- VAST approval rate
- Stock turnover rate

⚠️ Alerts:
- Promotor belum clock in
- Target not on track
- Stock critical level
- Pending approvals
```

---

## ⚙️ YANG SATOR/SPV KELOLA

### **1. Team Management:**
- Tambah/Hapus promotor
- Pindah toko (rotasi)
- Ubah status (Official/Training)
- Set hierarchy

### **2. Target Setting:**
- Set target bulanan per promotor
- Adjust target mid-month (kalau perlu)
- Copy from previous month
- Bulk apply to team

### **3. Order Approval:**
- Review daily orders
- Approve/Reject
- Send to warehouse (Discord)
- Track history

### **4. Stock Management:**
- Input stok gudang harian
- Monitor stok ready per toko
- Generate rekomendasi order
- Alert critical stock

### **5. Monitoring & Follow-up:**
- Check promotor activities
- Send reminders/motivation
- Give feedback
- Handle underperformers

---

## 🔄 DAILY WORKFLOW SATOR/SPV

### **Pagi (07:00-09:00)**
1. **Buka Dashboard Monitoring**
   - Lihat siapa sudah clock in
   - Cek ada alert/masalah?
   
2. **Follow-up Promotor:**
   - Yang belum clock in → send reminder
   - Yang performa turun → motivasi

### **Siang (11:00-14:00)**
1. **Monitor Sales:**
   - Cek dashboard sellout
   - Lihat progress vs target
   - Identify top/bottom performer

2. **Approve Orders:**
   - Review pending orders
   - Check stock availability
   - Approve/Reject

### **Sore (15:00-17:00)**
1. **Send Daily Report:**
   - Compile all approved orders
   - Send to Discord (warehouse team)
   - Update SPV/Manager

2. **Stock Management:**
   - Update stok gudang
   - Check critical alerts
   - Generate rekomendasi order

### **Malam (19:00-20:00)**
1. **Review Day:**
   - Achievement hari ini?
   - Issues yang perlu di-handle?
   - Plan untuk besok

2. **Weekly (End of Week):**
   - Set/adjust targets kalau perlu
   - Team meeting via Discord Voice
   - Export reports for management

---

## 📱 PRIORITAS FITUR UNTUK REBUILD

### **Priority 1: MONITORING & REPORTING (Week 1-2)**
1. Dashboard Monitoring (Checklist status)
2. Dashboard Sellout (Performance)
3. Basic alerts & notifications

### **Priority 2: MANAGEMENT (Week 3-4)**
4. Set Target Promotor
5. Kelola Tim (CRUD promotor)
6. Export & Discord integration

### **Priority 3: OPERATIONS (Week 5-6)**
7. Sell In (Order approval)
8. Stok Management
9. VAST Finance monitoring

### **Priority 4: ADVANCED (Week 7-8)**
10. Rekomendasi Order (AI-based)
11. Historical analysis
12. AI Insights

---

**NEXT:** Mau saya detail-kan workflow per halaman SATOR/SPV seperti untuk Promotor? Atau lanjut ke Admin features?
