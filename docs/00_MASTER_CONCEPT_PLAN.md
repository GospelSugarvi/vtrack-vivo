# 📋 PLANNING SESSION - 5 Januari 2026

**Duration:** ~30 menit  
**Focus:** Admin-First Design & Struktur Organisasi  
**Status:** In Progress (Lanjut besok)

---

## ✅ YANG SUDAH DI-LOCK HARI INI

### **🔒 1. KONSEP ADMIN (FOUNDATION)**

**Paradigm Shift:**
```
❌ OLD: Code menyimpan aturan bisnis (hardcode)
✅ NEW: Code hanya tahu POLA, Admin atur ISI & ATURAN

Prinsip:
- Kode tidak menyimpan angka
- Kode tidak tahu produk apa
- Kode tidak tahu bonus berapa
- Semua itu DATA yang diatur admin
```

**Admin Adalah:**
- Pemilik aturan bisnis
- Pengendali perubahan
- Penjaga umur panjang sistem
- Pengganti kehadiran developer di masa depan

**Admin HARUS Bisa Mengontrol (Tanpa Coding):**
1. Struktur Organisasi (Area, SPV, SATOR, Promotor, Toko)
2. User & Akses (tambah, edit, role, assign)
3. Area & Ekspansi (tambah area baru)
4. Produk (tambah, edit, kategori, fokus)
5. **Aturan Bonus** (range harga, rasio, periode) ⭐ CRITICAL
6. Target & Progress (set, edit, monitor)

---

### **🔒 2. STRUKTUR ORGANISASI HIERARKI**

**4 LEVELS (LOCKED!):**

```
Level 1: MANAGER AREA
         └─ Alberto
         └─ Handle multiple area (sekarang: Area Kupang)
         └─ Future: Admin decide (assign ke Alberto atau Manager baru)

Level 2: SPV (Supervisor)
         └─ Gery (Area Kupang)
         └─ 1 Area = 1 SPV
         └─ Report ke Manager Area

Level 3: SATOR (Sales Team Leader)
         └─ Antonio (handle ~belasan toko)
         └─ Andri (handle ~belasan toko)
         └─ Report ke SPV

Level 4: PROMOTOR (Field Sales)
         └─ 1 Promotor = 1 Toko (fixed, tidak multiple)
         └─ 1 Toko bisa isi 1-5 promotor
         └─ Report ke SATOR
```

**Key Facts:**
- Current: Hanya Area Kupang
- Future: Bisa expand (Sumba, Flores Timur, Flores Barat, dll)
- Area adalah konsep geografis flexible (kota, pulau, kabupaten)
- Semua struktur & relasi → Diatur Admin (tanpa coding)

**Relasi:**
```
Promotor → Works at → Toko (1 toko fixed)
Promotor → Reports to → SATOR

SATOR → Handles → Toko (belasan toko)
SATOR → Reports to → SPV (detail workflow TBD)

SPV → Handles → Area (1 area = 1 SPV)
SPV → Reports to → Manager Area (detail workflow TBD)

Manager Area → Handles → Multiple Area
Manager Area → Reports to → (None, top level)
```

---

## ✅ TARGET SYSTEM - LOCKED! 🎯

### **📋 5 JENIS TARGET**

#### **1. TARGET BULANAN (Omzet Total - Rupiah)**
```
Metrik: Rupiah (Rp)
Source: SEMUA produk yang dilaporkan promotor
├─ Produk Tipe Fokus (≥2jt): Y400, Y29, V-Series, iQoo, X-Series
└─ Produk Non-Fokus (<2jt): Semua produk murah

Level: Manager, SPV, SATOR, Promotor (semua punya)
Periode: 1 bulan penuh
Follow-up: 4x weekly (30%-25%-20%-25%) - tracking only

Contoh:
Promotor A - Target: Rp 10 juta
Penjualan: Y400 (21jt) + Y29 (5jt) + Produk murah (3jt) = Rp 29 juta
Achievement: 29/10 = 290% 🟠 Gold
```

#### **2. TARGET TIPE FOKUS (Produk ≥2jt - Unit/Qty) ⭐ 2 LEVEL!**
```
STRUKTUR:

Level 1: TARGET TIPE FOKUS UMUM (Total)
└─ Total semua produk tipe fokus (≥2jt)
   Termasuk yang TIDAK punya target (iQoo, X-Series)

Level 2: TARGET DETAIL PER PRODUK
├─ Y400 (punya target)
├─ Y29 (punya target)
└─ V-Series (punya target)

Validation: Total Detail ≥ Target Umum (minimal sama, boleh lebih)

Contoh SPV Gery:
├─ Target Umum: 100 unit
└─ Target Detail:
    ├─ Y400: 50 unit
    ├─ Y29: 30 unit
    └─ V-Series: 25 unit
    Total: 105 unit ✅ (105 ≥ 100, valid!)

Penjualan Actual:
├─ Y400: 55 unit
├─ Y29: 25 unit
├─ V-Series: 30 unit
├─ iQoo: 5 unit (no target, tapi masuk total umum!)
└─ X-Series: 3 unit (no target, tapi masuk total umum!)
Total: 118 unit

Achievement:
├─ Tipe Fokus Umum: 118/100 = 118% 🟠
├─ Y400: 55/50 = 110% 🟠
├─ Y29: 25/30 = 83% 🔵
└─ V-Series: 30/25 = 120% 🟠

Catatan:
✅ Semua level (Manager, SPV, SATOR, Promotor) punya 2 level target
✅ Produk tanpa target (iQoo, X-Series) tetap tracked & masuk total umum
✅ Admin bisa tambah/ubah produk & target (flexible)
```

#### **3. TARGET TIKTOK FOLLOWERS (Bulanan - Tracking Harian)**
```
Metrik: Jumlah follower baru
Target: Bulanan (contoh: 25 follower/bulan)
Tracking: Harian (input berapa follower dapat hari ini)
Flexible: Boleh 0 hari ini, 3 besok (total akhir bulan yang dihitung)
Follow-up: TIDAK pakai sistem follow-up mingguan

Contoh:
Target Januari: 25 follower → Actual: 28 follower
Achievement: 28/25 = 112% 🟠
```

#### **4. TARGET PROMOSI POST (Bulanan - Tracking Harian)**
```
Metrik: Jumlah posting promosi
Target: Bulanan (contoh: 50 posting/bulan)
Tracking: Harian
Follow-up: TIDAK pakai follow-up mingguan

Contoh:
Target: 50 posting → Actual: 47 posting
Achievement: 47/50 = 94% 🟢
```

#### **5. TARGET VAST FINANCE (Bulanan - Tracking Harian)**
```
Metrik: Jumlah pengajuan kredit
Target: Bulanan (contoh: 25 pengajuan/bulan)
Tracking: Harian
Follow-up: TIDAK pakai follow-up mingguan

Contoh:
Target: 25 pengajuan → Actual: 22 pengajuan
Achievement: 22/25 = 88% 🔵
```

---

### **🔄 FOLLOW-UP SYSTEM (Tracking Only)**

```
┌────────────┬──────────┬──────────┬──────────────────┐
│ Week       │ Tanggal  │ % Target │ Applies To       │
├────────────┼──────────┼──────────┼──────────────────┤
│ Follow-Up 1│ 1-7      │ 30%      │ Bulanan + Fokus  │
│ Follow-Up 2│ 8-14     │ 25%      │ Bulanan + Fokus  │
│ Follow-Up 3│ 15-22    │ 20%      │ Bulanan + Fokus  │
│ Follow-Up 4│ 23-31    │ 25%      │ Bulanan + Fokus  │
└────────────┴──────────┴──────────┴──────────────────┘

Karakteristik:
✅ Tracking/Monitoring saja (TIDAK ADA BLOCKING)
✅ Dashboard kasih warning kalau kurang target
✅ SATOR follow-up manual ke Promotor
✅ Admin bisa ubah % dan tanggal range

Tidak Berlaku:
❌ TikTok (tracking harian saja)
❌ Promosi (tracking harian saja)
❌ VAST Finance (tracking harian saja)
```

---

### **⚙️ WORKFLOW TARGET SETTING**

```
Waktu: Awal bulan (contoh: Januari awal)
Durasi: ~1 jam (cepat, selama angka sudah ada)

Step 1: Manager Area (Alberto)
├─ Tentukan angka target untuk semua level:
│  ├─ Manager Area (diri sendiri)
│  ├─ SPV (Gery)
│  ├─ SATOR (Antonio, Andri)
│  └─ Promotor (semua promotor)
└─ Kirim via WhatsApp ke Admin

Step 2: Admin
├─ Terima angka dari Manager
├─ Input ke sistem (UI Admin Target Management)
├─ Urutan: Manager → SPV → SATOR → Promotor
├─ Sistem validasi otomatis
└─ Save & Publish

Step 3: Manager Area (Alberto)
├─ Cek di Dashboard Manager
├─ Verifikasi angka sudah benar
└─ Done ✅
```

---

### **✅ VALIDATION RULES**

#### **A. Hierarchy Validation**
```
Total target bawahan ≥ Target atasan

Contoh:
SPV Target: Rp 150 juta
├─ SATOR Antonio: Rp 75 juta
└─ SATOR Andri: Rp 75 juta
Total: Rp 150 juta ✅

Jika < Rp 150 juta → ERROR
```

#### **B. Detail vs Umum Validation**
```
Total Detail ≥ Target Umum (minimal sama, boleh lebih)

VALID:
Target Umum: 100 unit
Detail: Y400=50, Y29=30, V-Series=25
Total: 105 unit ✅ (lebih = lebih ambisius)

INVALID:
Target Umum: 100 unit
Detail: Y400=40, Y29=30, V-Series=20
Total: 90 unit ❌ (kurang dari umum!)
```

#### **C. Realita Bisnis**
```
✅ Target bawahan LEBIH BESAR dari atasan = NORMAL
   Reason: Atasan kasih safety margin

Contoh:
Manager: 500 unit
SATOR breakdown:
├─ Antonio: 280 unit
└─ Andri: 280 unit
Total: 560 unit ✅ (lebih dari 500, OK!)
```

---

### **📊 ACHIEVEMENT COLOR CODING**

```
🔴 0-50%   = Red (Gagal)
🟡 51-75%  = Yellow (Kurang)
🔵 76-90%  = Blue (Cukup)
🟢 91-100% = Green (Bagus)
🟠 >100%   = Gold/Orange (Exceed)

Achievement dihitung:
✅ Per jenis target (terpisah)
✅ Per produk (untuk tipe fokus)
```

---

### **🔧 ADMIN CONTROL (Features)**

#### **Target Management:**
```
✅ Set target bulanan (omzet) semua level
✅ Set target tipe fokus (umum + detail) semua level
✅ Copy target dari bulan sebelumnya (bulk)
✅ Bulk set (set semua promotor area sekaligus)
✅ Edit target (kapan saja, history tracked)
✅ View achievement real-time
✅ Export report (Excel/PNG/WhatsApp)
✅ Validation rules (otomatis)
```

#### **Product Management:**
```
✅ Tambah produk baru (nama, harga, kategori)
✅ Set produk masuk "Tipe Fokus" (≥2jt)
✅ Set produk fokus mana yang PUNYA target
✅ Set produk fokus mana yang TIDAK PUNYA target
✅ Ubah kategori produk
✅ Active/Inactive product
```

#### **Follow-Up Settings:**
```
✅ Set % breakdown (default: 30-25-20-25)
✅ Set tanggal range (default: 1-7, 8-14, 15-22, 23-31)
✅ Enable/Disable follow-up per jenis target
✅ Set alert/notification
```

#### **Target Activation (Per Periode):**
```
✅ Enable/Disable target per jenis per bulan
   Admin bisa aktifkan/nonaktifkan target tertentu

Contoh:
Januari 2026:
├─ Target Bulanan: ACTIVE ✅
├─ Target Tipe Fokus: ACTIVE ✅
├─ Target TikTok: INACTIVE ❌ (belum mau pakai)
├─ Target Promosi: ACTIVE ✅
└─ Target VAST: INACTIVE ❌ (belum mau pakai)

Februari 2026:
├─ Target TikTok: ACTIVE ✅ (diaktifkan kembali)
└─ Target VAST: ACTIVE ✅ (diaktifkan kembali)

Use Case:
- Bulan tertentu tidak pakai target TikTok
- Admin toggle OFF untuk bulan itu
- Target TikTok tidak muncul di dashboard/input
- Bulan depan bisa toggle ON lagi
```

---

## 📋 AGENDA BESOK (Lanjutan)

### **Priority 1: Finalisasi TARGET SYSTEM**
- Jawab 8 pertanyaan di atas
- Lock konsep target
- Design admin UI untuk target

### **Priority 2: BONUS RULES** ⭐⭐⭐
```
Konsep (belum dibahas):
- Multi-rule system
- Range harga (min-max)
- Rasio hitung (2=1, 1=1, dll)
- Bonus per hitungan
- Periode berlaku
- Area berlaku
- User type (official/training)
- Status (active/inactive)

Critical karena:
- Aturan sering berubah
- Produk baru terus keluar
- Promo periode tertentu
- Tidak boleh hardcode!
```

### **Priority 3: PRODUCT MANAGEMENT**
```
- Dynamic product list
- Kategori (Y-Series, V-Series, dll)
- Product fokus
- Harga SRP
- Active/Inactive
- Periode availability
```

### **Priority 4: PERMISSION & ACCESS**
```
- Manager Area lihat apa
- SPV lihat apa
- SATOR lihat apa
- Promotor lihat apa
- Data filtering rules
```

### **Priority 5: REPORTING STRUCTURE**
```
Detail workflow (yang TBD):
- SATOR report ke SPV gimana
- SPV report ke Manager gimana
- Dashboard per level
- Metrics apa yang ditampilkan
```

---

## 📊 PROGRESS TRACKING

**Phase: Planning & Analysis**

```
Completed:
✅ Admin Concept (Foundation) - 100%
✅ Struktur Organisasi - 100% LOCKED
✅ Target System - 100% LOCKED 🎉
✅ Bonus System (Promotor & SATOR) - 100% LOCKED 🎉
✅ UI/UX Promotor - 100% LOCKED 🎉
✅ UI/UX SATOR - 100% LOCKED 🎉
✅ UI/UX SPV - 100% LOCKED 🎉
✅ Weekly Target Tracking System - 100% LOCKED 🎉
✅ XP/Level Gamification - DEFERRED (Not Priority)
✅ Reporting Structure - 100% (Covered in UI/UX & Schema)
✅ Permission & Access - 100% LOCKED (PERMISSION_ACCESS_SYSTEM.md)
✅ Product Management - 100% LOCKED (PERMISSION_ACCESS_SYSTEM.md)
✅ Database Schema - 100% LOCKED (SCHEMA_DESIGN_2026.md)

Overall Planning Progress: 100% - READY FOR NEW PROJECT 🚀
```

---

## 💡 KEY INSIGHTS HARI INI

1. **Admin-First Design = Game Changer**
   - Semua aturan bisnis jadi data, bukan code
   - Sistem hidup lama tanpa developer
   - Perubahan cepat tanpa coding

2. **Struktur Organisasi Clear**
   - 4 level hierarchy
   - Relasi jelas
   - Scalable untuk ekspansi

3. **Area = Konsep Flexible**
   - Bisa kota, pulau, kabupaten
   - Admin yang define
   - Mendukung ekspansi natural

4. **1 Promotor = 1 Toko (Fixed)**
   - Tidak ada promotor jaga multiple toko
   - Work location jelas
   - Responsibility clear

---

## 📝 NOTES & REMINDERS

**Untuk Besok:**
1. ✅ Fokus finalisasi Target System dulu
2. Jangan asumsi - semua info dari user
3. Tanya detail sebelum design
4. Lock konsep sebelum implement

**Critical Rules:**
- No hardcoding business rules
- Admin controls everything
- Flexible & scalable
- Historical data integrity

---

**Next Session:** Besok (6 Januari 2026)  
**Focus:** Target System Finalization + Bonus Rules  
**Status:** Ready to continue! ✅
