# 📊 REPORTING STRUCTURE
**Date:** 8 Januari 2026  
**Status:** CONFIRMED (Based on Existing System)

---

## 🎯 OVERVIEW

Sistem ini **sudah tidak pakai Discord**. Semua notifikasi dan reporting akan:
1. In-app notification
2. Export (Excel/Image)
3. Copy text untuk WhatsApp (manual share)
4. Built-in Chat (Future - perlu planning terpisah)

---

## 📋 LAPORAN PROMOTOR

### **1. Laporan Stok**
**Waktu:** Setiap ada stok masuk/berubah
**Isi:**
- IMEI produk masuk
- Tipe stok (Fresh/Display/Chip)
- Produk yang kosong (need restock)
- Cuci gudang items

### **2. Laporan AllBrand (Malam)**
**Waktu:** Setiap malam (end of day)
**Isi:**
```
DATA PENJUALAN per BRAND per PRICE RANGE:
├─ VIVO (auto dari sistem)
├─ Samsung (manual input)
├─ Oppo (manual input)
├─ Realme (manual input)
├─ Xiaomi (manual input)
└─ Infinix (manual input)

Price Ranges:
├─ < 2 Juta
├─ 2-4 Juta
├─ 4-6 Juta
└─ > 6 Juta

DATA LEASING (penjualan per leasing):
├─ HCI
├─ Kredivo
├─ Indodana
├─ FIF
├─ Kredit Plus
└─ Vast Finance

JUMLAH PROMOTOR per brand di toko:
├─ Vivo (auto)
├─ Samsung, Oppo, Realme, Xiaomi, Infinix (manual)
```

### **3. Laporan Penjualan (Setiap Transaksi)**
**Waktu:** Setiap input penjualan
**Isi:**
- IMEI
- Produk
- Harga jual
- Tipe barang (Fresh/Chip/Cuci Gudang)
- Jenis pembayaran (Cash/Kredit)
- Leasing (jika kredit)
- Foto customer (optional)

### **4. Laporan Promosi Medsos**
**Waktu:** Setiap hari (malam)
**Isi:**
- Platform (TikTok, Instagram, Facebook, WhatsApp, YouTube)
- Screenshot bukti posting
- Notes

### **5. Pengajuan VAST Finance**
**Waktu:** Setiap ada pengajuan kredit
**Isi:**
- Data customer (nama, telp, pekerjaan, penghasilan)
- Foto KTP
- Produk yang diajukan
- Status (Pending → Approved/Rejected)

### **6. Laporan Follower TikTok**
**Waktu:** Setiap dapat follower baru
**Isi:**
- Username TikTok
- Screenshot bukti

### **7. Absensi (Clock In)**
**Waktu:** Setiap pagi
**Isi:**
- Selfie foto
- GPS location
- Timestamp

---

## 📋 LAPORAN SATOR

### **1. Dashboard Monitoring**
**Isi:**
- Checklist aktivitas harian semua promotor
  - ☑ Absensi
  - ☑ Jualan
  - ☑ Stok
  - ☑ Promosi
- Alert: Promotor belum aktivitas

### **2. Dashboard Sellout**
**Isi:**
- Total omzet tim
- Total unit terjual
- Achievement vs target
- Weekly breakdown
- Top performers
- Underperformers
- Fokus products tracking
- Market share (allbrand comparison)

### **3. Input Stok Gudang**
**Waktu:** Setiap pagi
**Isi:**
- Stok per produk di gudang
- Stok OTW (On The Way)
- Method: Screenshot + AI parse ATAU manual input

### **4. Order Recommendation & Tracking (Sell-In)**
**Isi:**
- Generated recommendation per toko
- Status: Sent → Approved/Rejected → Submitted → Delivered

### **5. Dashboard VAST Team**
**Isi:**
- Total aplikasi tim
- Approved/Rejected/Pending count
- Per promotor breakdown
- Approval rate

---

## 📤 EXPORT FORMATS

### **1. Excel (.xlsx)**
**Available for:**
- Sellout summary (daily/weekly/monthly)
- Per promotor detail
- AllBrand comparison
- VAST applications
- Order history

**Content:**
- Raw data dengan semua kolom
- Summary sheets
- Charts (optional)

### **2. Image (PNG/JPG)**
**Available for:**
- Dashboard summary card
- Achievement graphs
- Leaderboard
- Team comparison

**Used for:**
- Share ke WhatsApp
- Share ke grup

### **3. Text (Copy)**
**Available for:**
- WhatsApp message format
- Quick share

**Template sudah ada:**
```
📌 **Laporan Allbrand - {tanggal}**
👤 **Promotor**: {nama}
🏬 **Toko**: {toko}
📍 **Area**: {area}

═══════════════════
📊 **Penjualan per Kategori (Today/MTD)**
═══════════════════

<2 Juta
• Vivo {today}/{mtd} | Samsung {today}/{mtd} | Oppo {today}/{mtd}
• Realme {today}/{mtd} | Xiaomi {today}/{mtd} | Infinix {today}/{mtd}

2-4 Juta
• [same format...]

═══════════════════
🏦 **Leasing (Today/MTD)**
═══════════════════
• HCI {today}/{mtd} | Kredivo {today}/{mtd} | Indodana {today}/{mtd}
• FIF {today}/{mtd} | Kredit+ {today}/{mtd} | Vast {today}/{mtd}

═══════════════════
👥 **Promotor**
═══════════════════
• Vivo: {count} | Samsung: {count} | Oppo: {count}
• Realme: {count} | Xiaomi: {count} | Infinix: {count}
```

---

## 🔔 IN-APP NOTIFICATION (Replace Discord)

### **Notification Types:**

#### **For Promotor:**
```
1. Reminder (Pagi)
   └─ "Jangan lupa clock in hari ini!"

2. Target Alert
   └─ "Achievement kamu baru 50%, semangat!"

3. Bonus Info
   └─ "Bonus hari ini: Rp 150.000"

4. Transfer Request
   └─ "Ahmad (MTC) minta 2 unit Y400"

5. Transfer Approved
   └─ "Transfer 2 unit Y400 dari Panakukkang disetujui"
```

#### **For SATOR:**
```
1. Stock Input Alert
   └─ "Ahmad (MTC) input 5 unit baru"

2. Allbrand Submitted
   └─ "Ahmad sudah submit laporan allbrand"

3. Chip Request
   └─ "Ahmad minta approval chip Y400 (IMEI: xxx)"

4. Low Stock Alert
   └─ "MTC: Y400 tinggal 1 unit"

5. Promotor Inactive
   └─ "Ahmad belum clock in hari ini"

6. Order Status
   └─ "MTC approved order Rp 25jt"
```

#### **For SPV/Admin:**
```
1. Daily Summary
   └─ "{tanggal}: 15 promotor aktif, 2 tidak clock in"

2. Target Achievement
   └─ "Tim NIO: 75% achievement bulan ini"

3. Anomaly Alert
   └─ "Stock mismatch di MTC: -2 unit"
```

---

## 📱 BUILT-IN CHAT (Future Feature)

**Status:** Perlu planning terpisah

**Scope:**
- 1-on-1 chat (Promotor ↔ SATOR)
- Group chat (Tim)
- Share reports via chat
- Push notification support

---

## ✅ SUMMARY

| Report Type | Who | Frequency | Export Options |
|-------------|-----|-----------|----------------|
| Clock In | Promotor | Daily (pagi) | - |
| Penjualan | Promotor | Per transaksi | - |
| Stok | Promotor | Per update | - |
| AllBrand | Promotor | Daily (malam) | Excel, Text |
| Promosi | Promotor | Daily | - |
| VAST App | Promotor | Per pengajuan | - |
| Follower | Promotor | Per follower | - |
| Gudang | SATOR | Daily (pagi) | - |
| Sellout | SATOR/SPV | On demand | Excel, Image |
| VAST Team | SATOR/SPV | On demand | Excel |
| Order | SATOR | Daily | Excel |

**Notification:** In-app only (no Discord)
**Share:** Export + manual share ke WhatsApp

---

**Status:** Reporting Structure - 100% LOCKED ✅
