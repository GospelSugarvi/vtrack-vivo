# UI/UX Planning - SATOR ROLE (Complete)
**Session:** 13-14 January 2026  
**Status:** 🔒 LOCKED  

---

## 📱 APP STRUCTURE

### Bottom Navigation (4 Tabs)
| Tab | Fungsi |
|-----|--------|
| 🏠 Home | Dashboard + Today + KPI + Alert + Quick Access |
| 📋 Workplace | Hub Menu Kerja (9 menu) |
| 👥 Tim | Obrolan + Toko + Checklist |
| 👤 Profil | Personal + Settings |

---

## 🏠 TAB 1: HOME

### Layout:
1. **Header** - Avatar, Nama, Area, Jumlah Promotor, Jumlah Toko, 🔔 Notif, ⚙️ Settings
2. **Today Status** - Penjualan hari ini (unit + Rp + jumlah promotor jual), Aktivitas tim
3. **KPI Saya (Bulanan)** - 4 komponen dengan bobot
4. **Perlu Perhatian** - Alert (late, no clock, belum lapor)
5. **Quick Access** - Sell Out, Tim, Leader, Workplace

### KPI Components (Bobot):
| Komponen | Bobot |
|----------|-------|
| Sell Out All (Rp) | 40% |
| Sell Out Fokus (Unit) | 30% |
| Sell In All | 20% |
| KPI MA | 10% |

### Weekly Target Tracking:
```
Target Bulanan didistribusi per minggu:
├── Minggu ke-1 (1-7): 30%
├── Minggu ke-2 (8-14): 25%
├── Minggu ke-3 (15-22): 20%
└── Minggu ke-4 (23-31): 25%

Berlaku untuk:
├── Sell Out All (Rupiah)
└── Sell Out Fokus (Unit: Y400, Y29s, V60 Lite)

Dashboard menampilkan:
├── Target minggu ini vs Actual
├── Cumulative progress
├── Per Promotor achievement
└── Warning jika kurang target
```

---

## 📋 TAB 2: WORKPLACE (Hub Menu Kerja)

### 9 Menu:
| # | Menu | Fungsi |
|---|------|--------|
| 1 | 📊 Sell Out | Summary + Live Jualan + Per Toko + Per Promotor |
| 2 | 📦 Sell In | Gudang + Rekomendasi + Order + Achievement |
| 3 | 📋 Aktivitas Tim | Toko → Promotor → Detail aktivitas |
| 4 | 🏆 Leaderboard | Ranking Harian + Live Feed + AI |
| 5 | 💰 KPI & Bonus | 4 Komponen + Poin + Reward Khusus |
| 6 | 🔢 IMEI Normal | Penormalan + Status + Anti-miss |
| 7 | 🏪 Visiting | Dashboard + Checklist |
| 8 | 📅 Jadwal | Approve + Kalender Tim |
| 9 | 📤 Export | Excel + Share |

---

## 👥 TAB 3: TIM (Unified Communication + Checklist)

### Struktur:
```
👥 TIM
│
├── 💬 Obrolan Tim (semua 8 promotor) ← @mention
│
└── 🏪 List Toko (+ completion %)
    └── Detail Toko
        ├── 💬 Obrolan Toko ← @mention
        └── 📋 Checklist
            └── Per Promotor → Status aktivitas
```

### Checklist Promotor (8 item):
| # | Aktivitas | Waktu | Wajib |
|---|-----------|-------|-------|
| 1 | ✅ Clock-in | Pagi | ✅ |
| 2 | 💵 Sell Out | Sepanjang hari | ⏳ |
| 3 | 📦 Laporan Stok | Harian | ✅ |
| 4 | 📣 Promosi/TikTok | Harian | ✅ |
| 5 | 👥 Follower TikTok | Harian | ✅ |
| 6 | 📱 VAST Finance | Jika ada | ⏳ |
| 7 | 📊 AllBrand | Malam | ✅ |
| 8 | 📋 Validasi Stok | Malam | ✅ |

---

## 👤 TAB 4: PROFIL

### Screens:
1. **Main** - Info diri + KPI summary + Menu
2. **Laporan Kinerja** - KPI breakdown + Trend + Per Toko
3. **Riwayat Reward** - History + Status cair
4. **Pengaturan Notifikasi** - Toggle per kategori

---

## 📦 SELL-IN (7 Screens)

### Screen 1: Dashboard
- Achievement bulan ini (Target Rupiah)
- Stok Gudang summary
- Status Toko (Urgent/Low/OK)
- Order Pending

### Screen 2: Stok Gudang
- **Input:** Upload foto / Paste JSON
- **Parse:** Stok ready saja (bukan stok OTW)
- **Filter:** Hilangkan DemoLive
- **Kategori:** 🟢 Banyak | 🟡 Cukup | 🔴 Kritis | ⚫ Kosong
- **Urutan:** Murah → Mahal (by Tipe, Varian, Warna)
- **Action:** Download PNG untuk share ke toko

### Screen 3: List Toko
- Status per toko (produk kosong, < minimal)
- [Buat Order →] button

### Screen 4: Rekomendasi
- Tabel per Tipe + Varian + Warna
- Kolom: PRODUK | VARIAN | WARNA | REORDER | HARGA
- ⚠️ Tidak tampilkan kolom stok gudang/minimal
- Download PNG untuk share

### Screen 5: Response Toko (BARU)
- Toko bisa: ✅ Terima Semua | ❌ Tolak Semua | ⚠️ Sebagian
- Edit qty per produk
- Simpan order final

### Screen 6: Pending List
- Order menunggu / approved / rejected

### Screen 7: Achievement
- **Filter Harian:** 30 hari terakhir
- **Filter Bulanan:** Semua bulan
- Per Toko breakdown

---

## 🏪 VISITING (4 Screens)

### Screen 1: Dashboard
- Smart sorting: 🔴 Urgent → 🟡 Perhatian → 🟢 OK
- Last visit, Achievement, Issues

### Screen 2: Pre-Visit
- Data toko + Issues + Stok + Riwayat visit

### Screen 3: Visit Form
- Foto (min 1)
- Checklist (display, harga tag, poster, promotor, stok)
- Catatan visit
- Follow-up action

### Screen 4: Success
- Konfirmasi tersimpan

---

## 📅 JADWAL (4 Screens)

### Flow Bulanan:
- **Submit:** Tanggal 25-28 bulan sebelumnya
- **Deadline Submit:** Tanggal 28
- **Deadline Approve:** Tanggal 30
- **Berlaku:** Bulan depan

### Screen 1: Dashboard
- Status: Approved / Pending / Belum Submit
- Deadline countdown

### Screen 2: Review Jadwal
- Detail per hari (Shift + Jam)
- Coverage check (gap detection)
- [Approve] [Reject]

### Screen 3: Kalender Tim
- Full week/month view
- Semua promotor per toko
- Issues detection

### Screen 4: Reject
- Pilih alasan
- Kirim notifikasi ke promotor

---

## 🏆 LEADERBOARD (4 Screens)

### Screen 1: Ranking
- TOP 3 highlight (foto, nama, bonus)
- Full list ranking
- Scope filter (Tim Saya / Area)
- Date filter (Hari Ini / Minggu / Bulan)

### Screen 2: Live Feed
- **AI Motivator** (pinned)
- **Sales Cards:**
  - Foto avatar + Nama + Toko
  - Foto jualan (customer + HP)
  - Produk + Harga + Bonus
  - Tipe Bayar: 💳 Cash / Kredit
  - Tipe Customer: 👤 Walk-in / 📞 VIP Call
  - Note dari Promotor
  - Reactions: 👏🔥💪
  - Comments

### Screen 3: Post Manual
- Tulis pengumuman
- Attach gambar (optional)
- Target audience

### Screen 4: Puji Promotor
- Template pujian cepat
- Publish ke Live Feed + Notifikasi

---

## 💰 KPI & BONUS

### KPI Breakdown:
| Komponen | Bobot |
|----------|-------|
| Sell Out All | 40% |
| Sell Out Fokus | 30% |
| Sell In All | 20% |
| KPI MA | 10% |

### Bonus Poin Table:
| Range Harga | Poin |
|-------------|------|
| Rp 3.5-4jt | 8 |
| Rp 4-4.5jt | 10 |
| Rp 4.5-6jt | 14 |
| > Rp 6jt | 18 |

1 Poin = Rp 1.000

---

## 🔢 IMEI NORMALISASI

### Kondisi:
- Tidak semua toko perlu normalisasi (ditandai admin)
- Promotor konfirmasi saat Lapor Jual → OTOMATIS masuk

### Status Flow:
```
⏳ Baru Masuk → 📤 Dikirim → ✅ Normal → 🎯 Sudah Scan
```

### Anti-Miss System:
- Push Notif saat Normal
- Badge Promotor permanen
- Reminder 18:00 dan 20:00
- [Ingatkan] button

---

## 🔗 ALIGNMENT PROMOTOR ↔ SATOR

| Fitur | Promotor | SATOR |
|-------|----------|-------|
| Sell Out | Lapor Jual | Lihat Live + Summary |
| Jadwal | Submit bulan depan | Approve/Reject |
| Checklist | Submit aktivitas | Monitor completion |
| Stok | Input stok toko | Monitor + Order |
| Chat | Obrolan Toko | Obrolan Tim + Toko |
| IMEI | Kirim ke SATOR | Normalkan + Track |
| Leaderboard | Lihat + React | Lihat + Comment + Puji |

---

## 🔔 NOTIFIKASI SATOR

| Trigger | Notifikasi |
|---------|------------|
| Promotor jual | "Ahmad jual Y400 - Rp 150k" |
| Promotor late | "Farhan clock-in terlambat" |
| No sell 2 hari | "Gita belum jual 2 hari" |
| Kandidat Official | "Budi eligible kandidat" |
| Warning Downgrade | "Citra warning downgrade" |
| Jadwal pending | "3 jadwal menunggu approval" |
| Jadwal submit | "Ahmad submit jadwal Feb" |
| IMEI perlu normal | "5 IMEI perlu normalisasi" |
| Stok urgent | "Giant: 5 produk kosong" |
| Chat @mention | "Ahmad mention kamu di Obrolan" |

---

## 📊 TOTAL SCREENS

| Module | Screens |
|--------|---------|
| Home | 1 |
| Sell Out | 4 |
| Sell In | 7 |
| Visiting | 4 |
| Jadwal | 4 |
| Tim | 3 |
| Leaderboard | 4 |
| Profil | 4 |
| **TOTAL** | **31** |

---

**Document Updated:** 14 January 2026  
**Status:** 🔒 COMPLETE & LOCKED
