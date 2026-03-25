# 🔧 ADMIN DASHBOARD SYSTEM
**Date:** 8 Januari 2026  
**Status:** 100% LOCKED ✅

---

## 🎯 OVERVIEW

Admin Dashboard adalah bagian dari **1 app yang sama** dengan promotor/SATOR/SPV.
- Role-based menu (login → detect role → tampilkan menu)
- Mobile-first, tapi bisa akses via web browser juga
- Admin kontrol SEMUA aturan bisnis (tidak ada hardcode)

---

## 📋 ADMIN MODULES

### **1. DASHBOARD OVERVIEW**
```
Real-time summary:
├─ Total User Aktif (Promotor, SATOR, SPV)
├─ Total Toko
├─ Today's Sales (Rp + Unit)
├─ Today's Achievement (%)
├─ Active Chat Count
├─ Pending Issues (alerts)
└─ Quick Actions
```

---

### **2. USER MANAGEMENT**
```
Features:
├─ View all users (list + filter + search)
├─ Add new user
├─ Edit user details
├─ Assign role (Promotor/SATOR/SPV/Admin)
├─ Assign to toko (for Promotor)
├─ Assign toko to SATOR (which SATOR handles which toko)
├─ Change promotor status (Official ↔ Training)
├─ Activate/Deactivate user
└─ Delete user (soft delete, data tetap)

Actions:
├─ Pindah toko promotor → Auto update chat membership
├─ Non-aktifkan → Auto remove from chat
└─ Semua otomatis sync
```

---

### **17. HIERARCHY MANAGEMENT** ⭐ VISUAL TREE
```
Purpose: View dan manage struktur organisasi lengkap

Hierarchy Structure:
Manager Area → SPV → SATOR → Promotor → Toko

Tabs:
├─ 📊 VIEW - Tree view hierarchy
├─ ✏️ EDIT - Assign/pindah
└─ 📜 HISTORY - Log perubahan

VIEW HIERARCHY:
┌─────────────────────────────────────────────────────────────┐
│ 🏢 MAKASSAR AREA                                            │
│ ├── 👔 SPV: Gery Herlambang                                 │
│ │   ├── 👤 SATOR: Albert Tana (Makassar Selatan)            │
│ │   │   ├── 🏪 Transmart MTC                                │
│ │   │   │   ├── Ahmad (Official)                            │
│ │   │   │   └── Farhan (Training)                           │
│ │   │   ├── 🏪 Giant Alauddin                               │
│ │   │   │   └── Gita (Training)                             │
│ │   │   └── 🏪 ... (more toko)                              │
│ │   ├── 👤 SATOR: Nio (Makassar Utara)                      │
│ │   │   └── ... (toko + promotor)                           │
│ │   └── 👤 SATOR: ... (more)                                │
│ └── 👔 SPV: ... (if any)                                    │
└─────────────────────────────────────────────────────────────┘

EDIT ACTIONS:
├─ Assign Promotor ke SATOR
├─ Assign SATOR ke SPV
├─ Assign Promotor ke Toko
├─ Pindah Promotor (Toko/SATOR)
├─ Pindah SATOR (SPV)
└─ Berlaku mulai (tanggal efektif)

AUTO-CASCADE RULES:
├─ Promotor pindah Toko beda SATOR → auto pindah SATOR
├─ Toko pindah SATOR → semua Promotor ikut pindah
└─ SATOR pindah SPV → semua Toko+Promotor ikut

HISTORY LOG:
├─ Siapa pindah dari mana ke mana
├─ Kapan (timestamp)
├─ Oleh siapa (admin)
├─ Catatan/alasan
└─ Filter by: user, toko, date range
```

---

### **3. TOKO MANAGEMENT**
```
Features:
├─ View all toko (list + filter + search)
├─ Add new toko
├─ Edit toko details (nama, alamat, grade)
├─ Assign SATOR to toko (who handles)
├─ Assign promotor ke toko
├─ Create/Edit SPC group (toko cabang)
├─ Assign toko to SPC group
├─ Set toko grade (A/B/C/D)
├─ Activate/Deactivate toko
└─ View toko stock summary

SPC Group:
├─ Create group: "Transmart" (multi-branch)
├─ Add toko to group
└─ View group total stock/sales
```

---

### **4. PRODUCT MANAGEMENT**
```
Features:
├─ View all products (list + filter + search)
├─ Add new product
├─ Edit product details:
│   ├─ Nama produk
│   ├─ Varian (RAM/ROM)
│   ├─ Warna (per SKU)
│   ├─ Harga SRP
│   ├─ Harga Gudang (modal)
│   ├─ Series (Y/V/X/iQoo)
│   └─ Flags:
│       ├─ is_fokus (Tipe Fokus)
│       ├─ is_cuci_gudang (Clearance)
│       └─ is_demo (Demo unit)
├─ Add new color variant
├─ Deactivate product
└─ View product stock per toko

Auto-calculated (view only):
├─ Margin (SRP - Harga Gudang)
├─ Total stock (all toko)
└─ Sales velocity
```

---

### **5. BONUS SETTINGS** ⭐ CRITICAL
```
Features:
├─ Range-Based Incentive
│   ├─ Add/Edit/Delete range
│   ├─ Set range: min_harga, max_harga
│   ├─ Set bonus: Official amount, Training amount
│   ├─ Effective date (kapan mulai berlaku)
│   └─ History (audit trail)
│
├─ X-Series Flat Bonus
│   ├─ Set product → flat bonus amount
│   └─ Add/remove products
│
├─ 2:1 Ratio Products
│   ├─ Add/remove products to 2:1 list
│   ├─ Set bonus per unit (setelah rasio)
│   └─ Set bonus amount: Official, Training
│
├─ Achievement Tunjangan
│   ├─ Set threshold ranges
│   ├─ Set tunjangan per range
│   └─ Only for Official promotor
│
└─ Other Special Rules
    ├─ Add custom rules as needed
    └─ Future-proof for new promo types

UI Example (Range-Based):
┌────────────────────────────────────────────────┐
│ BONUS RANGE-BASED                              │
├────────────────────────────────────────────────┤
│ Range          │ Official │ Training │ Action  │
├────────────────┼──────────┼──────────┼─────────┤
│ < 2 Juta       │ Rp 0     │ Rp 0     │ [Edit]  │
│ 2 - 4 Juta     │ Rp 25k   │ Rp 22.5k │ [Edit]  │
│ 4 - 6 Juta     │ Rp 45k   │ Rp 40k   │ [Edit]  │
│ > 6 Juta       │ Rp 90k   │ Rp 80k   │ [Edit]  │
└────────────────┴──────────┴──────────┴─────────┘
[+ Add New Range]
```

---

### **6. TARGET MANAGEMENT**
```
Features:
├─ View all targets (per period)
├─ Set target per Promotor:
│   ├─ Target Omzet (Rp)
│   ├─ Target Tipe Fokus (unit)
│   ├─ Target per Product (Y400, Y29, V-Series)
│   └─ Other targets...
├─ Set target per SATOR (aggregate)
├─ Set target per SPV (aggregate)
├─ Bulk set (apply same to all)
├─ Copy from previous month
├─ View achievement tracking
└─ Export target vs actual report

Validation:
├─ Child targets must sum ≤ parent target
└─ Warning jika tidak balance
```

---

### **7. SATOR REWARD SETTINGS**
```
Features:
├─ KPI Categories
│   ├─ Set category (Sell Out, Sell In, etc)
│   ├─ Set weight (%)
│   └─ Set calculation rules
│
├─ Point System
│   ├─ Set point per action
│   ├─ Set bonus per point
│   └─ Set threshold for rewards
│
├─ Special Product Rewards
│   ├─ Add product → reward amount
│   └─ Set conditions
│
└─ Penalty Settings
    ├─ Set threshold for penalty
    └─ Set penalty amount
```

---

### **8. STOCK MANAGEMENT**
```
Features:
├─ View all stock (all toko)
├─ View stock per toko
├─ View stock per product
├─ Stock adjustment:
│   ├─ Select toko, product
│   ├─ Input adjustment (+/-)
│   ├─ Select reason
│   └─ Submit (logged)
├─ View adjustment history
├─ View transfer history
├─ Discrepancy reports
└─ Export stock report

Alerts:
├─ Low stock warning
├─ Discrepancy detected
└─ Unusual transfer patterns
```

---

### **15. ACTIVITY MANAGEMENT** ⭐ DYNAMIC
```
Purpose: Admin kontrol aktivitas promotor yang aktif/nonaktif
Aktivitas OFF = tidak muncul di mana-mana

Features:
├─ View semua aktivitas
├─ Toggle ON/OFF per aktivitas
├─ Schedule ON/OFF otomatis per periode
├─ Buat aktivitas baru (tanpa code)
├─ Edit aktivitas existing
├─ Delete aktivitas (soft delete)
└─ History perubahan

Aktivitas Default:
├─ Clock-in (Pagi, Wajib)
├─ Sell Out (All day, Optional)
├─ Laporan Stok (Harian, Wajib)
├─ Promosi/TikTok (Harian, Wajib)
├─ Follower TikTok (Harian, Wajib) ← Bisa OFF
├─ VAST Finance (Jika ada, Optional)
├─ AllBrand (Malam, Wajib)
└─ Validasi Stok (Malam, Wajib)

Tipe Input yang Didukung:
├─ Foto Only (1-3 foto)
├─ Foto + Text
├─ Number Input
├─ Checklist (Yes/No items)
└─ Link URL

Saat Aktivitas OFF:
├─ Tidak muncul di Promotor app
├─ Tidak muncul di SATOR checklist
├─ Tidak ada reminder
├─ Tidak dihitung di KPI
└─ Tidak muncul di report

Saat Buat Aktivitas Baru:
├─ Set nama + icon + deskripsi
├─ Pilih tipe input
├─ Set waktu (Pagi/Siang/Harian/Malam)
├─ Set wajib/optional
├─ Set reminder timing
├─ Set hitung di KPI atau tidak
└─ OTOMATIS muncul di Promotor + SATOR

UI Example:
┌─────────────────────────────────────────────────────────────┐
│ AKTIVITAS PROMOTOR                                          │
├─────────────────────────────────────────────────────────────┤
│ AKTIVITAS       │ STATUS │ WAJIB │ WAKTU   │ ACTION         │
├─────────────────┼────────┼───────┼─────────┼────────────────┤
│ Clock-in        │ [●] ON │ ✅    │ Pagi    │ [Edit]         │
│ Sell Out        │ [●] ON │ ⏳    │ All day │ [Edit]         │
│ Laporan Stok    │ [●] ON │ ✅    │ Harian  │ [Edit]         │
│ Promosi/TikTok  │ [●] ON │ ✅    │ Harian  │ [Edit]         │
│ Follower TikTok │ [○] OFF│ -     │ -       │ [Edit]         │
│ VAST Finance    │ [●] ON │ ⏳    │ Jika ada│ [Edit]         │
│ AllBrand        │ [●] ON │ ✅    │ Malam   │ [Edit]         │
│ Validasi Stok   │ [●] ON │ ✅    │ Malam   │ [Edit]         │
└─────────────────┴────────┴───────┴─────────┴────────────────┘
[+ Tambah Aktivitas Baru]

Jadwal Aktivitas:
┌─────────────────────────────────────────────────────────────┐
│ AKTIVITAS       │ PERIODE      │ STATUS                     │
├─────────────────┼──────────────┼────────────────────────────┤
│ Follower TikTok │ 1-31 Jan     │ 🔴 OFF                     │
│                 │ 1 Feb - ...  │ 🟢 ON (SCHEDULED)          │
└─────────────────┴──────────────┴────────────────────────────┘
```

---

### **16. AI SETTINGS** ⭐ CONFIGURABLE PROMPTS
```
Purpose: Admin kontrol semua AI features tanpa hardcode prompt

AI Features:
├─ AI Business Review (Mingguan)
├─ AI Motivator (Leaderboard Feed)
└─ AI Comment (Live Sales Feed)

Per Feature Config:
├─ Status: ON/OFF
├─ Prompt (System + User template)
├─ Variabel yang tersedia
├─ Test prompt langsung
├─ Schedule (jika applicable)
└─ History perubahan

AI BUSINESS REVIEW:
┌─────────────────────────────────────────────────────────────┐
│ Status: [●] Aktif                                           │
│ Periode: Mingguan (7 hari) ← Fixed                          │
│                                                             │
│ Auto Generate:                                              │
│ [✓] Enable                                                  │
│ Hari: [Senin]  Jam: [08:00]                                 │
│ Notifikasi ke SATOR setelah generate                        │
│                                                             │
│ Output Sections:                                            │
│ [✓] Executive Summary                                       │
│ [✓] Metrics Dashboard                                       │
│ [✓] Insights (Positif/Perhatian/Kritis)                     │
│ [✓] Tim Performance                                         │
│ [✓] Rekomendasi                                             │
│ [✓] Action Items                                            │
│                                                             │
│ [Edit Prompt →]                                             │
└─────────────────────────────────────────────────────────────┘

AI MOTIVATOR:
┌─────────────────────────────────────────────────────────────┐
│ Status: [●] Aktif                                           │
│ Frekuensi: Setiap [2] jam                                   │
│ Jam aktif: [08:00] - [20:00]                                │
│                                                             │
│ Variabel: {{total_unit}}, {{target}}, {{top_seller}}, etc   │
│ [Edit Prompt →]                                             │
└─────────────────────────────────────────────────────────────┘

AI COMMENT (Sales Feed):
┌─────────────────────────────────────────────────────────────┐
│ Status: [●] Aktif                                           │
│ Delay: [30] detik setelah post                              │
│                                                             │
│ Special triggers:                                           │
│ [✓] First sale of the day                                   │
│ [✓] Big deal (> Rp 5jt)                                     │
│ [✓] Achievement milestone (50%, 75%, 100%)                  │
│                                                             │
│ Variabel: {{nama}}, {{produk}}, {{bonus}}, {{ranking}}, etc │
│ [Edit Prompt →]                                             │
└─────────────────────────────────────────────────────────────┘

EDIT PROMPT UI:
├─ System Prompt (instruksi untuk AI)
├─ User Prompt Template (dengan {{variabel}})
├─ Variabel yang tersedia (auto-complete)
├─ [Test Generate] - preview hasil
├─ History perubahan
└─ [Restore Last Version]
```

---

### **9. ORDER MANAGEMENT**
```
Features:
├─ View all orders (rekomendasi)
├─ Filter by SATOR, toko, status
├─ View order detail
├─ Override order status (if needed)
├─ View order history
└─ Export order report
```

---

### **10. REPORT & ANALYTICS**
```
Features:
├─ Sales reports (daily/weekly/monthly)
├─ Achievement reports
├─ Bonus calculation reports
├─ Stock reports
├─ Order reports
├─ User activity reports
├─ Export to Excel
├─ Export to Image
└─ Schedule auto-report (future)
```

---

### **11. ANNOUNCEMENT**
```
Features:
├─ Create announcement
├─ Edit announcement
├─ Delete announcement
├─ View read status (who read, who not)
└─ Pin important announcement

Only Admin/SPV can create
All users can read
```

---

### **12. SYSTEM SETTINGS**
```
Features:
├─ Chat retention period (default: 1 month)
├─ Announcement retention (default: 6 months)
├─ Image compression settings
├─ Notification settings
├─ App version info
└─ Other configs

Future:
├─ API keys management
├─ Integration settings
└─ Backup settings
```

---

### **18. WEEKLY TARGET SETTINGS** ⭐ CONFIGURABLE
```
Purpose: Admin kontrol pembagian target per minggu
Date ranges = LOCKED (tidak bisa diubah user)
Persentase = Configurable oleh Admin

Default:
┌────────────┬──────────┬──────────┐
│ Week       │ Tanggal  │ % Target │
├────────────┼──────────┼──────────┤
│ Minggu 1   │ 1-7      │ 30%      │
│ Minggu 2   │ 8-14     │ 25%      │
│ Minggu 3   │ 15-22    │ 20%      │
│ Minggu 4   │ 23-31    │ 25%      │
└────────────┴──────────┴──────────┘
Total: 100%

Features:
├─ Set persentase per minggu
├─ Tanggal LOCKED (1-7, 8-14, 15-22, 23-31)
├─ Validation: Total harus = 100%
├─ Berlaku untuk:
│   ├─ Sell Out All (Rupiah)
│   └─ Sell Out Fokus (Unit)
├─ TIDAK berlaku untuk:
│   ├─ TikTok Followers
│   ├─ Promosi Post
│   └─ VAST Finance
└─ Copy settings ke bulan berikutnya

UI:
┌─────────────────────────────────────────────────────────────┐
│ ⚙️ WEEKLY TARGET SETTINGS                                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ Periode: [Januari 2026 ▼]                                   │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ MINGGU   │ TANGGAL (LOCKED) │ PERSENTASE               ││
│ │──────────┼──────────────────┼──────────────────────────││
│ │ Minggu 1 │ 1 - 7            │ [ 30 ] %                 ││
│ │ Minggu 2 │ 8 - 14           │ [ 25 ] %                 ││
│ │ Minggu 3 │ 15 - 22          │ [ 20 ] %                 ││
│ │ Minggu 4 │ 23 - 31          │ [ 25 ] %                 ││
│ │──────────┼──────────────────┼──────────────────────────││
│ │ TOTAL    │                  │ 100% ✅                  ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ ⚠️ Total harus = 100%                                       │
│                                                             │
│ [💾 Simpan]  [📋 Copy ke Bulan Selanjutnya]                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### **13. STOK MINIMAL SETTINGS** ⭐ NEW
```
Purpose: Set standard minimum stock per Toko + Tipe + Varian + Warna
Setiap toko bisa punya standard berbeda.

Features:
├─ View stok minimal per toko
├─ Set stok minimal per produk:
│   ├─ Pilih Toko
│   ├─ Pilih Tipe (Y21D, Y400, V60, X200, dll)
│   ├─ Pilih Varian (4+128, 8+256, dll)
│   ├─ Pilih Warna (Hitam, Putih, Gold, dll)
│   ├─ Set minimum qty
│   └─ Save
├─ Bulk set by Grade:
│   ├─ Grade A → Apply default minimal (from template)
│   ├─ Grade B → Apply default minimal
│   ├─ Grade C → Apply default minimal
│   └─ Grade D → Apply default minimal
├─ Copy settings antar toko
├─ Import from template
├─ Export settings
└─ History changes (audit trail)

Logic:
├─ Jika stok toko < minimal → Alert + Rekomendasi Order
├─ Jika minimal = 0 → Produk tidak perlu distok di toko ini
└─ Override: Custom per toko-produk > Grade template

UI Example:
┌─────────────────────────────────────────────────────────────┐
│ STOK MINIMAL - Transmart MTC (Grade A)        [Copy To...]  │
├─────────────────────────────────────────────────────────────┤
│ [Filter: All ▼] [Series: All ▼] [Search...]                 │
├─────────────────────────────────────────────────────────────┤
│ PRODUK              │ VARIAN  │ WARNA  │ MIN │ STOK │Action │
├─────────────────────┼─────────┼────────┼─────┼──────┼───────┤
│ Y21D                │ 4+128   │ Hitam  │ 3   │ 5 ✅ │[Edit] │
│ Y21D                │ 4+128   │ Putih  │ 3   │ 2 ⚠️ │[Edit] │
│ Y21D                │ 4+128   │ Gold   │ 3   │ 0 ❌ │[Edit] │
│ Y400                │ 8+256   │ Purple │ 2   │ 3 ✅ │[Edit] │
│ Y400                │ 8+256   │ Blue   │ 2   │ 1 ⚠️ │[Edit] │
│ V60 Lite            │ 8+256   │ Black  │ 2   │ 2 ✅ │[Edit] │
│ V60 Lite            │ 8+256   │ Blue   │ 2   │ 0 ❌ │[Edit] │
│ X200 Pro            │ 12+512  │ Black  │ 1   │ 1 ✅ │[Edit] │
└─────────────────────┴─────────┴────────┴─────┴──────┴───────┘
[+ Add Product] [📥 Apply Grade Template] [📤 Export]

Default Grade Template:
┌────────────────────────────────────────────────────────────┐
│ GRADE TEMPLATE - Atur default minimal per Grade            │
├───────────┬─────────┬─────────┬─────────┬─────────┬────────┤
│ Series    │ Tier    │ Grade A │ Grade B │ Grade C │Grade D │
├───────────┼─────────┼─────────┼─────────┼─────────┼────────┤
│ Y-series  │ < 2jt   │ 5       │ 3       │ 2       │ 1      │
│ Y-series  │ 2-3jt   │ 4       │ 3       │ 2       │ 1      │
│ Y-series  │ 3-4jt   │ 3       │ 2       │ 1       │ 1      │
│ V-series  │ 3-4jt   │ 3       │ 2       │ 1       │ 1      │
│ V-series  │ 4-6jt   │ 2       │ 1       │ 1       │ 0      │
│ X-series  │ > 6jt   │ 1       │ 1       │ 0       │ 0      │
│ iQOO      │ 4-6jt   │ 2       │ 1       │ 1       │ 0      │
└───────────┴─────────┴─────────┴─────────┴─────────┴────────┘
[Save Template]
```

---

### **14. KATEGORI STATUS STOK GUDANG** ⭐ NEW
```
Purpose: Set threshold untuk kategori status stok gudang
Banyak, Cukup, Kritis, Kosong

Features:
├─ Set threshold default (semua produk):
│   ├─ 🟢 Banyak: Stok ≥ X unit
│   ├─ 🟡 Cukup: Stok Y - Z unit
│   ├─ 🔴 Kritis: Stok 1 - W unit
│   └─ ⚫ Kosong: Stok = 0
├─ Set threshold per Series (optional):
│   ├─ Y-series: threshold berbeda
│   ├─ V-series: threshold berbeda
│   ├─ X-series: threshold berbeda
│   └─ iQOO: threshold berbeda
├─ History changes (audit trail)
└─ Preview: Lihat berapa produk di setiap kategori

Logic:
├─ Digunakan di tampilan Stok Gudang
├─ Digunakan untuk alert di Dashboard
└─ Urutan tampilan: Murah → Mahal (by Tipe, Varian, Warna)

UI Example:
┌─────────────────────────────────────────────────────────────┐
│ KATEGORI STATUS STOK GUDANG                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 📊 THRESHOLD DEFAULT                                        │
│ ┌───────────┬───────────────────────────────────┬─────────┐│
│ │ STATUS    │ KONDISI                           │ ACTION  ││
│ ├───────────┼───────────────────────────────────┼─────────┤│
│ │ 🟢 Banyak │ Stok ≥ [ 10 ] unit                │ [Edit]  ││
│ │ 🟡 Cukup  │ Stok [ 5 ] - [ 9 ] unit           │ [Edit]  ││
│ │ 🔴 Kritis │ Stok [ 1 ] - [ 4 ] unit           │ [Edit]  ││
│ │ ⚫ Kosong │ Stok = 0                          │ -       ││
│ └───────────┴───────────────────────────────────┴─────────┘│
│                                                             │
│ 📦 THRESHOLD PER SERIES (Override)                          │
│ ┌───────────┬─────────┬─────────┬─────────┬───────────────┐│
│ │ SERIES    │ BANYAK  │ CUKUP   │ KRITIS  │ ACTION        ││
│ ├───────────┼─────────┼─────────┼─────────┼───────────────┤│
│ │ Y-series  │ ≥ 15    │ 8-14    │ 1-7     │ [Edit]        ││
│ │ V-series  │ ≥ 10    │ 5-9     │ 1-4     │ [Edit]        ││
│ │ X-series  │ ≥ 5     │ 3-4     │ 1-2     │ [Edit]        ││
│ │ iQOO      │ ≥ 5     │ 3-4     │ 1-2     │ [Edit]        ││
│ └───────────┴─────────┴─────────┴─────────┴───────────────┘│
│                                                             │
│ [Save]                                                      │
└─────────────────────────────────────────────────────────────┘

Preview Hasil:
┌─────────────────────────────────────────────────────────────┐
│ 📊 CURRENT DISTRIBUTION                                     │
│ 🟢 Banyak: 32 produk (71%)                                  │
│ 🟡 Cukup: 8 produk (18%)                                    │
│ 🔴 Kritis: 3 produk (7%)                                    │
│ ⚫ Kosong: 2 produk (4%)                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔒 ADMIN ACCESS CONTROL

```
Who is Admin?
├─ Manager Area (Alberto) - Full Admin
├─ SPV (Gery) - Can access some admin features
└─ Future: Can add more Admin users

Admin Levels (if needed later):
├─ Super Admin: Full access everything
├─ Admin: Most features, no system settings
└─ Limited Admin: Specific modules only

Current: Single Admin level (full access)
```

---

## 📱 UI APPROACH

```
1 App for all roles:
├─ Login → Detect role → Show appropriate menu
├─ Admin menu is different from Promotor menu
├─ But same app, same installation

Mobile-first but web-ready:
├─ Flutter app for mobile
├─ Responsive for tablet
├─ Can access via web (Flutter web) if needed

Admin-specific considerations:
├─ Tables need horizontal scroll on mobile
├─ Complex forms split into steps
├─ Bulk operations available
└─ Quick search/filter everywhere
```

---

## ✅ SUMMARY

| Module | Admin Control |
|--------|---------------|
| Users | Full CRUD |
| Toko | Full CRUD |
| Products | Full CRUD |
| Bonus Promotor | Full CRUD |
| Targets | Full CRUD |
| SATOR Rewards | Full CRUD |
| **SPV Rewards** | **Full CRUD** |
| Stock | View + Adjust |
| Orders | View + Override |
| Reports | View + Export |
| Announcements | Full CRUD |
| Settings | Full Access |
| **Stok Minimal** | **Full CRUD (per Toko+Produk+Warna)** |
| **Kategori Status Stok** | **Full CRUD (Banyak/Cukup/Kritis)** |
| **Activity Management** | **Full CRUD (ON/OFF + Buat Baru)** |
| **AI Settings** | **Full CRUD (Prompts + Schedule)** |
| **Hierarchy Management** | **View Tree + Assign + History** |
| **Weekly Target Settings** | **Set % per Minggu (Date LOCKED)** |

**Prinsip: Admin kontrol SEMUA aturan bisnis. Tidak ada hardcode.**

---

**Status:** Admin Dashboard System - 100% LOCKED ✅
