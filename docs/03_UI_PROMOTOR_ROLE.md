# UI/UX Planning - PROMOTOR ROLE (Complete)
**Session:** 13 January 2026  
**Status:** 🔒 LOCKED  

---

## 📱 APP STRUCTURE

### Bottom Navigation (5 Tabs)
| Tab | Icon | Sub-tabs |
|-----|------|----------|
| Home | 🏠 | - |
| Laporan | 📋 | - |
| Leaderboard | 🏆 | Ranking, Live Feed |
| Chat | 💬 | Obrolan, Aktivitas |
| Profil | 👤 | - |

**Technical:** No loading between tabs (pre-load data)

---

## 🏠 TAB 1: HOME

### Layout:
1. **Header** - Avatar, Nama, Toko, Area, 🔔 Notif, ⚙️ Settings
2. **Hero Card** - Bonus bulanan + progress + target harapan
3. **Quick Stats** (4 chip) - Pencapaian, Fokus, VAST, Ranking
4. **Today Status** - Tanggal, Shift, Clock-in status
5. **Quick Actions** (8 icon grid) - Clock-in, Jual, Stok, VAST, Promosi, Follower, AllBrand, Cari Stok
6. **Recent Activity** - Last 3 activities

---

## 📋 TAB 2: LAPORAN

### Grouped by Category:

**⏰ ABSENSI:**
- Clock-in (Foto + SS DingTalk + Status + Note)
- Jadwal Saya (Per-day shift: Pagi/Siang/Libur)

**📦 STOK:**
- Input Stok (Fresh/Chip/Cuci Gudang + IMEI scan/bulk)
- Validasi Stok (IMEI list + konfirmasi + koreksi)
- Cari Stok (Per area SATOR)

**💰 PENJUALAN:**
- Lapor Jual (IMEI → auto-fill produk + payment type)
- VAST Finance (Form lengkap + approve pending)

**📣 PROMOSI:**
- Lapor Promosi (Platform + foto + link)
- Lapor Follower (Username + screenshot)
- Lapor AllBrand (Competitor qty per range harga)

---

## 🏆 TAB 3: LEADERBOARD

### Sub-tab: Ranking
- Top 3 highlight (by BONUS amount)
- Full list ranking

### Sub-tab: Live Feed
- **AI Motivator** (sticky di atas)
- Sales cards: Foto promotor, produk, bonus, timestamp
- Reactions: 👏🔥💪
- Comments dari SATOR/SPV/Manager
- AI automatic comments on special events

---

## 💬 TAB 4: CHAT

### Sub-tab: Obrolan
- Free discussion dengan leader (SATOR/SPV)
- Group chat per toko

### Sub-tab: Aktivitas
- All reports + comments
- SATOR can comment on each activity

---

## 👤 TAB 5: PROFIL

### Info Diri:
- Foto, Nama, Status (Official/Training)
- Toko, Area, SATOR

### Menu:
- 📅 Jadwal Saya
- 📊 Riwayat Penjualan (per tanggal + detail)
- 💰 Riwayat Bonus (per transaksi + tag rasio)
- 🔔 Pengaturan Notifikasi
- ℹ️ Tentang Aplikasi
- 🚪 Logout

---

## 📊 DETAIL PAGES (5 Total)

### 1. Detail Bonus
- Total + progress
- Rincian per tipe (Normal 1:1 vs Rasio 2:1)
- Catatan: "Jika ganjil, pembulatan ke bawah"
- Riwayat transaksi

### 2. Detail Sell Out (Pencapaian)
- Total pencapaian (Rp) + progress + target
- **WEEKLY TARGET TRACKING:**
  - Minggu ke-1 (1-7): Target 30%
  - Minggu ke-2 (8-14): Target 25%
  - Minggu ke-3 (15-22): Target 20%
  - Minggu ke-4 (23-31): Target 25%
  - Progress actual vs target minggu ini
  - Warning jika kurang target minggu
- Tipe Fokus (Unit): Y400, Y29s, V60 Lite (target vs actual per minggu)
- Breakdown pembayaran: Cash vs Kredit
- Detail leasing: VAST, Kredivo, HCI, dll
- Breakdown customer: Walk-in vs VIP Call

### 3. Detail VAST Finance
- Total pengajuan + progress
- Status: Approved / Pending / Rejected
- Konversi (Pending → Approved)
- Riwayat pengajuan

### 4. Detail Promosi
- Total postingan
- Per platform: TikTok / Instagram / Facebook
- Riwayat dengan link

### 5. Detail Follower
- Total follower + progress + target
- Riwayat follower

---

## 🔔 NOTIFIKASI

### Jenis:
| Trigger | Notifikasi |
|---------|------------|
| Jadwal diapprove | "Jadwal Februari sudah diapprove oleh SATOR" |
| Validasi stok malam | "Waktunya validasi stok toko!" |
| Pesan dari SATOR | "SATOR Ahmad: [message]" |
| Bonus milestone | "Selamat! Bonus kamu sudah Rp 1jt!" |
| Ranking naik | "Kamu naik ke #3 di leaderboard!" |
| AI mention | "AI: Ahmad on fire dengan 3 penjualan!" |

### Settings:
- Toggle per jenis notifikasi
- Waktu hening (22:00 - 07:00)

---

## 📝 TERMINOLOGY

| ❌ Jangan Pakai | ✅ Pakai |
|----------------|---------|
| Omzet | Pencapaian |

---

## 🔗 FORM INPUT SUMMARY (10 Total)

| # | Form | Input | Foto |
|---|------|-------|------|
| 1 | Clock-in | SS DingTalk + Foto + Status | ✅ 2x |
| 2 | Jadwal | Per-day shift selection | ❌ |
| 3 | Input Stok | Status + Produk + IMEI | ❌ |
| 4 | Validasi Stok | IMEI confirmation + koreksi | ❌ |
| 5 | Lapor Jual | IMEI → auto-fill + payment | ✅ 1x |
| 6 | VAST Finance | Full application form | ✅ 2x |
| 7 | Lapor Promosi | Platform + foto + link | ✅ Multi |
| 8 | Lapor Follower | Username + screenshot | ✅ Multi |
| 9 | Lapor AllBrand | Qty per brand per range | ❌ |
| 10 | Cari Stok | Select produk → view toko | ❌ |

---

## 🔢 IMEI NORMALIZATION (Toko Tertentu)

### Kondisi:
- Tidak semua toko perlu normalisasi
- Hanya toko tertentu yang ditandai admin
- Promotor harus konfirmasi saat Lapor Jual

### Flow saat Lapor Jual:
```
1. Promotor scan IMEI
2. Sistem cek: Toko perlu normalisasi?
   - TIDAK → Selesai (langsung scan vChat)
   - YA → Dialog konfirmasi
3. Promotor tap [Ya, Kirim ke SATOR]
4. OTOMATIS masuk ke sistem SATOR
5. SATOR copy ke grup → Backoffice normalize
6. SATOR tandai Normal → Promotor dapat notif
7. Promotor scan di vChat → [Sudah Scan]
```

### Status IMEI:
| Status | Artinya |
|--------|---------|
| ⏳ Belum Kirim | Perlu kirim ke SATOR |
| 📤 Menunggu | Waiting backoffice |
| ✅ Normal | Ready scan di vChat |
| 🎯 Sudah Scan | Selesai |

### Halaman IMEI Normalisasi:
- Akses dari: Home badge, Laporan menu
- List IMEI per status
- [Copy IMEI] untuk scan di vChat
- [Sudah Scan] untuk konfirmasi

### Badge di Home:
- "X IMEI Perlu Kirim!" (jika ada belum kirim)
- "X IMEI Perlu Scan!" (jika ada yang sudah normal)

### Anti-Miss System:
- Push notif saat IMEI sudah normal
- Reminder jam 18:00 dan 20:00
- Badge permanen sampai scan

---

**Document Created:** 13 January 2026  
**Status:** 🔒 COMPLETE & LOCKED
