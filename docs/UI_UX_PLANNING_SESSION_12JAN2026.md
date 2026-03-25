# UI/UX Planning Session - 12 January 2026

> **Status**: 🔒 LOCKED  
> **Focus**: SATOR Role + Promotor Role (Update)  
> **Next Session**: SPV Role

---

## 📋 SESSION SUMMARY

Detailed UI/UX planning for the Flutter mobile application, focusing on screen-by-screen breakdown with user flows, data display, and interactions.

---

## ✅ PROMOTOR ROLE (LOCKED)

### Features Completed:
| Feature | Description |
|---------|-------------|
| Dashboard + Ringkasan | Daily performance overview |
| Absensi/Clock-in + Note | Photo selfie + optional note |
| Jadwal Kerja Bulanan | **Flexible per-day shift selection** (Pagi/Siang/Libur) |
| Target Bonus Harapan | Personal monthly bonus target |
| 6 Laporan | Stok, Jual, Follower, Promosi, AllBrand, VAST |
| Dashboard Sell Out & VAST | Performance tracking |
| Cek Stok IMEI | Stock verification |
| Leaderboard | View + react (👏🔥💪) |
| Chat | Integrated with Chat Toko |
| Profil | Personal profile |

### Jadwal Kerja Rules:
- Promotor input jadwal per tanggal (tap calendar)
- Options: 🌅 Pagi (08:00-16:00), 🌇 Siang (13:00-21:00), 🔴 Libur
- Quick fill available (all pagi, all siang, selang-seling, libur minggu)
- Max 4 hari libur per bulan
- Must submit before deadline (e.g., 25th of previous month)
- Requires SATOR approval

---

## ✅ SATOR ROLE (LOCKED)

### 1. SELL-IN FEATURE (8 Screens)

| Screen | Description |
|--------|-------------|
| Dashboard Sell-In | Overview: warehouse stock, store status, pending orders |
| Scan Stok Gudang | AI parsing + JSON manual fallback + confirmation before save |
| List Toko | Filter by Urgent/Low/OK, show empty products |
| Generate Rekomendasi | Edit quantities, show margin, WhatsApp + Copy button |
| Pending List | Orders awaiting owner response |
| Update Status | Approved/Partial/Rejected with reasons |
| Submit ke VIVO Sell | Simple reminder + checkbox "Sudah input" |
| Achievement | Monthly performance tracking |

**Key Decisions:**
- Stok Gudang = Per Area (shared by all SATOR in same area)
- AI scan screenshot from official VIVO app
- JSON manual input if AI fails
- Confirmation dialog before saving (warns about overwrite)
- WhatsApp: Opens pre-filled message, user taps "Send"
- Copy button as alternative to WhatsApp
- Post-send confirmation dialog
- Submit to "VIVO Sell" app (manual input, cannot paste)

---

### 2. MONITORING TIM (11 Screens)

| Screen | Description |
|--------|-------------|
| Dashboard Harian | Ringkasan: clock-in, sellout, promosi, stok, VAST |
| Dashboard Bulanan | Target vs Pencapaian, Time Gone - 15% logic |
| List Promotor | All promotors with status, quick actions |
| Detail Promotor | ALL activities with PHOTOS and FULL DATA |
| Detail Promosi | Full size photos, platform, caption, link |
| Detail Sellout | Product, IMEI, photos, payment method |
| Detail Lap.Stok | Photo proof, stock list per product |
| Perlu Follow-up | List problematic promotors, batch select |
| Teguran Individual | Templates + custom message |
| Teguran Batch | Send to multiple promotors |
| Puji | Templates, send to Leaderboard Feed |

**Key Decisions:**
- Detail shows ALL data (photos, IMEI, numbers, timestamps)
- Tap "Lihat Detail" to drill down
- Laporan Stok & AllBrand: Only 1 promotor per store reports (assigned by SATOR)
- Time Gone - 15% = threshold for "On Track"

---

### 3. CHAT TOKO (2 Tabs)

| Tab | Description |
|-----|-------------|
| 💬 Chat | Free conversation (general discussion) |
| 📋 Aktivitas | Reports + Comments on each activity |

**Key Decisions:**
- Opsi B design: Separated tabs
- Activities tab shows all reports with ability to comment on each
- Reports: Absensi, Promosi, Penjualan, Stok
- Collapsed design for stores with many promotors (3+ = grouped)
- Penjualan always shows individually (important)
- Reactions: 👏🔥💪

---

### 4. VISITING (3 Steps - Simplified)

| Step | Description |
|------|-------------|
| 1. Dashboard | Smart sorting recommendations (Urgent/Perhatian/OK) |
| 2. Visit Screen | All-in-one: Photo + Data + Form (checklist + free text) |
| 3. Toast | "Visit berhasil!" → Auto return to dashboard |

**Key Decisions:**
- No GPS validation (photo only)
- Smart sorting: No Sell days, stock issues, performance below threshold
- Checklist for common findings
- Action plan checklist
- Optional additional photos
- Status: Pending → In Progress → Resolved
- SPV can comment on visit reports

---

### 5. LEADERBOARD + AI MOTIVATOR

**Components:**
| Component | Description |
|-----------|-------------|
| TOP 3 | Ranking by BONUS earned (not quantity) |
| List per Area | Sudah jual vs Belum jual per SATOR team |
| Live Feed | Sales notifications with PHOTOS + comments |
| AI Motivator | Contextual messages, event-driven |

**AI Motivator System:**
- Event-driven triggers (not polling)
- Caching layer (no constant DB queries)
- ~25 AI calls per area per day
- Context: Today's data, 7-day history, monthly achievement
- Triggers: New sale, scheduled checkpoints (12:00, 15:00, 18:00), milestones

**AI Context (what AI knows):**
- Current date/time, remaining work hours
- Who sold what (name, product, time, bonus)
- Who hasn't sold yet
- 7-day history (streak, trend)
- Monthly achievement vs time gone
- Special events (comeback, first-time, personal record)

**Access Control:**
| Role | View | React | Post |
|------|------|-------|------|
| Promotor | ✅ | ✅ | ❌ |
| SATOR | ✅ | ✅ | ✅ |
| SPV | ✅ | ✅ | ✅ |
| Manager | ✅ | ✅ | ✅ |

---

### 6. APPROVE JADWAL (3 Screens)

| Screen | Description |
|--------|-------------|
| Dashboard | Status (Approved/Pending/Not submitted), list pending |
| Detail Jadwal | Review jadwal, validasi otomatis, approve/reject |
| Kalender Tim | Full view all promotors, coverage check |

**Features:**
- View promotor's submitted schedule
- Auto-validation: Max off, not consecutive, coverage
- Approve/Reject with optional comment
- Quick "Approve All" for pending
- Export to Excel (for HRD)
- Integration with attendance (plan vs actual)

---

## ⏳ PENDING (Next Session)

| Role | Status |
|------|--------|
| SPV | 🔜 Next session |
| Manager | ⏳ Pending |
| Admin | ⏳ Pending |

---

## 📐 DESIGN PRINCIPLES ESTABLISHED

1. **Mobile-first**: Vertical scroll, card-based, touch-friendly
2. **Progressive disclosure**: Tap to see more details
3. **Efficiency**: Minimal steps, quick actions
4. **Transparency**: All data accessible with full detail
5. **Event-driven**: AI and notifications on events, not polling
6. **Caching**: Minimize database queries

---

## 🔗 RELATED DOCUMENTS

- [CHAT_SYSTEM_PLANNING.md](CHAT_SYSTEM_PLANNING.md) - Chat structure details
- [STOCK_ORDER_COMPLETE_FLOW.md](STOCK_ORDER_COMPLETE_FLOW.md) - Sell-In flow
- [BONUS_SYSTEM_FINAL.md](BONUS_SYSTEM_FINAL.md) - Bonus calculation
- [TECHNICAL_ARCHITECTURE_STANDARDS.md](TECHNICAL_ARCHITECTURE_STANDARDS.md) - Tech stack

---

**Document Created**: 12 January 2026  
**Last Updated**: 12 January 2026
