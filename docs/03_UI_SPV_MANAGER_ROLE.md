# UI/UX Planning - SPV ROLE (Complete)
**Session:** 14 January 2026  
**Status:** 🔒 LOCKED  

---

## 📱 APP STRUCTURE (Unified App)

### Bottom Navigation (4 Tabs)
| Tab | Fungsi |
|-----|--------|
| 🏠 Home | Dashboard + Overview + Alert |
| 📊 Monitoring | Sell Out + Sell In + Aktivitas + Visiting |
| 👥 Tim | Drill down: SATOR → Toko → Promotor |
| 👤 Profil | KPI + Reward + Settings |

---

## 🏠 TAB 1: HOME

### Layout:
1. **Header** - Avatar, Nama, Area, Jumlah SATOR/Toko/Promotor, 🔔 Notif
2. **Today Snapshot** - Quick view sell out & completion
3. **Weekly Progress** - Target minggu ini vs Actual (30-25-20-25%)
4. **Perlu Perhatian** - Alert critical items
5. **Top/Bottom SATOR** - Quick performance check
6. **Quick Actions** - Broadcast, Monitoring, Export

### UI Mockup:
```
┌─────────────────────────────────────────────────────────────┐
│ 🏠 SPV DASHBOARD                           📅 14 Jan 2026  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 👔 Gery Herlambang                                          │
│ SPV - Makassar Area                                         │
│ 👤 5 SATOR | 🏪 32 Toko | 👥 45 Promotor                    │
│                                                             │
│ 📊 TODAY SNAPSHOT                                           │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Sell Out: Rp 295.000.000 (85% daily target)             ││
│ │ Promotor Jual: 38/45 | Belum Jual: 7 ⚠️                 ││
│ │ Visit SATOR: 4/5 | Belum Visit: 1 ⚠️                    ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ ⚠️ PERLU PERHATIAN (Tap untuk detail)                       │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ 🔴 SATOR Nio: 30% Weekly Target (danger)                ││
│ │ 🔴 7 Promotor belum jual hari ini                       ││
│ │ 🔴 Giant Daya: Stok kosong 5 produk                     ││
│ │ 🟡 5 Promotor late clock-in                             ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ 📊 MINGGU KE-2 (Target 25%)                                 │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Total: Rp 72jt / Rp 87.5jt (82%)                        ││
│ │ [██████████████████░░░░] ⚠️ Kurang 15.5jt               ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ 🚀 QUICK ACTIONS                                            │
│ [📊 Monitoring]  [👥 Tim]  [💬 Broadcast]  [📤 Export]      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 TAB 2: MONITORING

### Sub-tabs:
1. **Sell Out** (Rupiah All + Unit Fokus)
2. **Sell In** (Achievement + Order)
3. **Aktivitas** (Completion Rate)
4. **Visiting** (Issue tracking)

### 1. SELL OUT MONITORING (Weekly Tracking)

```
┌─────────────────────────────────────────────────────────────┐
│ 📊 SELL OUT                                                 │
│ Filter: [Minggu Ini (8-14 Jan) ▼]                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 📊 SUMMARY (Minggu Ini)                                     │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ SELL OUT ALL (Targets: 25% of Monthly)                  ││
│ │ Target: Rp 87.5jt | Actual: Rp 72jt (82%) ⚠️            ││
│ │                                                         ││
│ │ TIPE FOKUS (Unit)                                       ││
│ │ Y400:    10 / 15 unit (66%) 🔴                          ││
│ │ Y29s:    20 / 25 unit (80%) ⚠️                          ││
│ │ V60Lite: 15 / 10 unit (150%) ✅                         ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ 🏆 SATOR PERFORMANCE                                        │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ SATOR      │ ALL (Rp) │ %    │ FOKUS (Unit) │ STATUS    ││
│ │────────────┼──────────┼──────┼──────────────┼───────────││
│ │ 🥇 Albert  │ Rp 25jt  │ 120% │ 15/12        │ ✅ Great  ││
│ │ 🥈 Dani    │ Rp 22jt  │ 105% │ 12/12        │ ✅ OK     ││
│ │    Rudi    │ Rp 15jt  │  70% │  8/12        │ ⚠️ Low    ││
│ │    Nio     │ Rp 5jt   │  25% │  2/12        │ 🔴 Bad    ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ Tap SATOR untuk drill down ke Toko & Promotor               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2. SELL IN MONITORING

- Target Sell In per SATOR vs Actual
- Stok Gudang Summary (Critical/Warning/Safe)
- Order status summary (Pending/Approved)

### 3. AKTIVITAS MONITORING

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 AKTIVITAS TIM                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ 📊 COMPLETION RATE (Today)                                  │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ Clock-in:    45/45  100% ✅                             ││
│ │ Sell Out:    38/45   85% ⚠️                             ││
│ │ Stok:        40/45   89% ⚠️                             ││
│ │ Promosi:     35/45   78% ⚠️                             ││
│ └─────────────────────────────────────────────────────────┐│
│                                                             │
│ ⚠️ BELUM LAPOR                                              │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ STOK: Hendra, Ayu, Rina, Budi C., Dewi                 ││
│ │ PROMOSI: Hendra, Ayu, Rina, + 7 lainnya                ││
│ │ [📢 Ingatkan Semua]                                     ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4. VISITING MONITORING

- Progress visit SATOR (Target visits vs Actual)
- Issue log (Open items & Resolution status)
- Foto visit feed (Latest visits)

---

## 👥 TAB 3: TIM (Drill Down)

### Structure:
**Level 1: List SATOR**
- Summary performance
- Quick chat/call buttons

**Level 2: Detail SATOR**
- KPI SATOR breakdown
- List Toko (Sorted by worst performing)
- List Promotor (Problematic ones highlighted)

**Level 3: Detail Toko**
- Stok status
- Sales history
- Assign promotor

**Level 4: Detail Promotor**
- Profile & KPI
- Activity logs
- Absensi & Shift

### Drill Down Logic:
1. Tap SATOR Nio (🔴)
2. Lihat Toko mana yang jeblok -> Giant Daya (🔴)
3. Tap Giant Daya -> Lihat Promotor Eko (🔴)
4. Chat Eko / Call SATOR Nio untuk fix issue

---

## 👤 TAB 4: PROFIL

### Components:
1. **Info Diri:** Foto, Nama, Area
2. **KPI SPV Bulanan:**
   - Aggregated achievement from all SATORs
   - Weekly milestones status
   - Estimated Reward calculation
3. **Menu:**
   - 📊 Laporan Kinerja (Full Report)
   - 💰 Riwayat Reward
   - 📤 Export Report (Excel/PDF)
   - 🔔 Pengaturan Notifikasi
   - ℹ️ Tentang Aplikasi
   - 🚪 Logout

---

## 🔔 NOTIFIKASI SPV

| Trigger | Message | Action |
|---------|---------|--------|
| SATOR < 50% Weekly | "⚠️ Nio baru capai 30% minggu ini!" | Open Detail Nio |
| Promotor No Sell | "🔴 3 Promotor di area Utara 0 sales 2 hari" | Open Monitoring |
| Stok Gudang Kosong | "🔴 Y29s Hitam stok gudang habis!" | Open Sell In |
| All Promotors Done | "✅ Semua aktivitas tim selesai hari ini" | - |
| Approval Request | "📝 Ada 3 jadwal pending approval" | Open Approval |

---

## ✅ CONFIRMED FEATURES
1. **Target:** Rupiah (Sell Out All), Unit (Sell Out Fokus)
2. **Weekly Tracking:** 30% - 25% - 20% - 25% distribution
3. **Drill Down:** Area → SATOR → Toko → Promotor
4. **Communication:** Broadcast & Direct Chat
5. **Alerts:** Real-time problem detection

