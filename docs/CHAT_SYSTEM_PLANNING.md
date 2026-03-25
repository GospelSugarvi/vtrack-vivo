# 💬 BUILT-IN CHAT SYSTEM
**Date:** 8 Januari 2026  
**Status:** 100% LOCKED ✅

---

## 🎯 OVERVIEW

Sistem chat terintegrasi dalam app, menggantikan Discord dan WhatsApp untuk komunikasi internal tim.

**Key Features:**
- Chat per Toko (dengan laporan data)
- Group chat (Tim SATOR, Global)
- Private 1-on-1
- Announcement channel
- Push notification
- Mention (@nama)
- Read receipts

---

## 📱 JENIS CHAT

### **1. CHAT TOKO (Contextual)**

```
Struktur:
├─ 1 toko = 1 grup chat
├─ Akses: Promotor di toko + SATOR + SPV
├─ Content: Data laporan + Chat
└─ Contoh: "Transmart MTC"

UI:
┌─────────────────────────────────────────┐
│ 🏪 TRANSMART MTC                        │
├─────────────────────────────────────────┤
│ PROMOTOR: Ahmad, Budi                   │
│                                         │
│ 📊 DATA HARI INI (Auto):                │
│ ┌─────────────────────────────────────┐ │
│ │ Absensi: ✅ Ahmad (08:00)            │ │
│ │         ❌ Budi (belum)              │ │
│ ├─────────────────────────────────────┤ │
│ │ Stok: 25 unit                        │ │
│ │ Sell Out: 5 unit (Rp 12.5jt)         │ │
│ │ Promosi: 3 post                      │ │
│ │ Achievement: 75% 🎯                  │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ 💬 CHAT:                                │
│ ┌─────────────────────────────────────┐ │
│ │ [SATOR Nio] 09:15                   │ │
│ │ "@Budi kenapa belum absen?"          │ │
│ │                        ✓✓ read       │ │
│ ├─────────────────────────────────────┤ │
│ │ [Budi] 09:20                        │ │
│ │ "Maaf pak, baru sampai toko"         │ │
│ │                        ✓✓ read       │ │
│ ├─────────────────────────────────────┤ │
│ │ [SPV] 09:25                         │ │
│ │ "Besok jangan terulang ya 👍"        │ │
│ │                        ✓ 1/2 read    │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ [📷] [Type message...        ] [Send]   │
└─────────────────────────────────────────┘
```

**Use case:**
- SATOR cek data promotor
- Langsung tegur/puji di chat
- Koordinasi langsung dengan toko

---

### **2. CHAT TIM SATOR**

```
Struktur:
├─ 1 SATOR = 1 grup tim
├─ Akses: Semua promotor under SATOR + SATOR + SPV
└─ Contoh: "Tim Nio" (17 promotor + Nio + SPV)

Fungsi:
├─ Broadcast ke semua promotor
├─ Diskusi tim
├─ Koordinasi umum
└─ Share info/tips
```

---

### **3. CHAT GLOBAL SPV**

```
Struktur:
├─ 1 grup untuk semua orang
├─ Akses: Semua SATOR + Semua Promotor + SPV
└─ Contoh: "Global Team"

Fungsi:
├─ Pengumuman umum
├─ Info company-wide
└─ Diskusi antar tim
```

---

### **4. PRIVATE CHAT (1-on-1)**

```
Struktur:
├─ Siapa saja bisa chat siapa saja
├─ Private (hanya 2 orang)
└─ Contoh: "Ahmad ↔ SATOR Nio"

Fungsi:
├─ Diskusi sensitif
├─ Masalah personal
├─ Coaching individual
└─ Request khusus
```

---

### **5. ANNOUNCEMENT CHANNEL (Read-Only)**

```
Struktur:
├─ 1 channel announcement
├─ WRITE: SPV & Admin only
├─ READ: Semua orang
└─ Read-only untuk non-SPV

Fungsi:
├─ Pengumuman resmi
├─ Kebijakan baru
├─ Target baru
├─ Info penting
└─ Event/promo

UI:
┌─────────────────────────────────────────┐
│ 📢 ANNOUNCEMENT                         │
├─────────────────────────────────────────┤
│ [SPV] 8 Jan 2026, 09:00                │
│ "Mulai bulan ini, target unit fokus    │
│  naik 10%. Target baru sudah di-set    │
│  di sistem. Semangat! 💪"              │
│                                         │
│ Read by: 28/35 ✓                        │
├─────────────────────────────────────────┤
│ [SPV] 5 Jan 2026, 14:00                │
│ "Reminder: Deadline laporan AllBrand   │
│  setiap hari max jam 21:00"            │
│                                         │
│ Read by: 35/35 ✓✓                       │
└─────────────────────────────────────────┘
```

---

## ⚡ FITUR CHAT

### **1. Push Notification**
```
- Notifikasi setiap ada chat baru
- Bisa di-mute per chat
- Badge counter di app icon
```

### **2. Mention (@nama)**
```
Ketik @A → muncul autocomplete:
├─ @Ahmad
├─ @Ani
├─ @All (mention semua orang di grup)
└─ etc.

Orang yang di-mention dapat notifikasi priority
```

### **3. Read Receipts**
```
Status message:
├─ ✓ Sent (terkirim)
├─ ✓✓ Read (dibaca)
└─ Bisa lihat siapa yang sudah/belum baca

View:
[Message text...]
✓✓ Read by 15/17
[Tap to see details]
```

### **4. Attachment**
```
Bisa kirim:
├─ 📷 Foto (camera)
├─ 🖼️ Gambar (gallery)
└─ ❌ File (tidak perlu)

Upload:
├─ Auto-compress
├─ Upload ke Cloudinary
└─ Preview thumbnail
```

### **5. Chat History**
```
Retention:
├─ Auto-delete setelah 1 bulan
├─ Atau bisa di-set oleh Admin
└─ Announcement history lebih lama (6 bulan?)
```

---

## 📜 ATURAN CHAT (CONFIRMED)

### **1. Auto-Creation (Otomatis)**
```
Chat Room dibuat OTOMATIS:
├─ Chat Toko: Auto saat toko dibuat
├─ Chat Tim SATOR: Auto saat SATOR assigned ke promotor
├─ Chat Global: Default 1 sudah ada
├─ Announcement: Default 1 sudah ada
├─ Private: User langsung bisa chat siapa saja

Admin TIDAK perlu setup manual!
```

### **2. Membership Control**
```
Kontrol Keanggotaan:

OTOMATIS (Auto-follow hierarchy):
├─ Promotor → Auto masuk grup toko sendiri
├─ SATOR → Auto masuk grup toko yang dia handle
├─ SPV → Auto masuk semua grup di bawahnya
└─ Tidak bisa leave sendiri

DIATUR ADMIN (Manual assign):
├─ Manager Area → Admin atur masuk grup mana
├─ SPV Trainer → Admin atur masuk grup mana
└─ Tidak otomatis masuk ke semua grup

PROMOTOR PINDAH TOKO:
├─ Admin pindahkan promotor (di user management)
├─ System auto: Keluar dari chat toko lama
├─ System auto: Masuk ke chat toko baru
└─ Promotor TIDAK bisa keluar sendiri

PROMOTOR RESIGN/NON-AKTIF:
├─ Admin non-aktifkan (di user management)
├─ System auto: Keluar dari semua grup
├─ Chat history tetap ada (tidak dihapus)
└─ Promotor tidak bisa akses lagi

ATURAN:
├─ Promotor/SATOR/SPV TIDAK bisa leave group sendiri
├─ Hanya Admin yang bisa keluarkan
└─ Semua otomatis mengikuti status user (kecuali Manager/Trainer)
```

### **3. Pin Message**
```
Siapa bisa Pin:
├─ SATOR ✅
├─ SPV ✅
├─ Admin ✅
├─ Promotor ❌

Fungsi:
├─ Pin message penting di atas chat
├─ Max pin: 3 messages per room (?)
└─ Unpin by who pinned or higher
```

### **4. Edit & Delete Message**
```
Edit Message:
├─ User bisa edit message sendiri ✅
├─ TIME LIMIT: 1 menit setelah kirim
├─ Setelah 1 menit → tidak bisa edit
├─ Show "edited" label
└─ Edit history tidak di-track (simple)

Delete Message:
├─ User bisa delete message sendiri ✅
├─ TIME LIMIT: 1 menit setelah kirim
├─ Setelah 1 menit → tidak bisa delete
├─ Show "message deleted" placeholder
└─ Permanent delete, tidak bisa recover
```

### **5. Reply/Quote Message**
```
Reply:
├─ Tap message → Reply
├─ Show quoted message di atas reply
├─ Scroll to original on tap quote
└─ Works dalam same room only
```

### **6. Emoji Reaction**
```
Reaction:
├─ Long-press message → Show emoji picker
├─ Quick reactions: 👍 ❤️ 😂 😮 😢
├─ Full emoji picker available
├─ Multiple users can react same emoji
└─ Show reaction count under message
```

### **7. Typing Indicator**
```
Typing:
├─ Show "Ahmad is typing..." saat user ketik
├─ Multiple: "Ahmad, Budi are typing..."
├─ Disappear after 3 seconds no activity
└─ Only show in active chat room
```

### **8. Online Status**
```
Status:
├─ 🟢 Online (app open)
├─ ⚪ Offline (app closed)
├─ Show in chat member list
├─ Show in private chat header
└─ Last seen: "Last seen 5 min ago"
```

### **9. Offline Queue**
```
Offline Mode:
├─ Message disimpan di local queue
├─ Auto-send saat kembali online
├─ Show "pending" indicator saat offline
├─ Sync semua saat reconnect
└─ Bisa baca chat history offline (cached)
```

### **10. Moderasi**
```
TIDAK ADA moderasi:
├─ Semua karyawan internal
├─ Semua chat work-related
├─ Trust system
└─ Admin tidak perlu monitor chat

Tidak ada:
├─ Report message
├─ Block user
├─ Mute chat (SEMUA harus bisa dilihat)
├─ Search (tidak perlu)
```

### **11. Notification Sound**
```
Sound:
├─ Sound saat chat baru masuk
├─ Beda sound untuk @mention (priority sound)
├─ Sound dapat di-off/on di settings HP
└─ Vibration juga
```

### **12. Forward Message**
```
Forward:
├─ Long-press message → Forward
├─ Pilih chat tujuan (grup atau private)
├─ Show "Forwarded" label
└─ Works untuk text dan image
```

### **13. Image Handling**
```
Upload:
├─ Auto-compress sebelum upload
├─ Max resolution: 1920px
├─ Quality: 80% JPEG
├─ Original file tidak disimpan
└─ Fast upload, hemat bandwidth
```

---

## 👥 AKSES MATRIX
|-----------|----------|-------|-----|-------|
| Toko (own) | ✅ R/W | ✅ R/W | ✅ R/W | ✅ R/W |
| Toko (other) | ❌ | ❌ | ✅ R/W | ✅ R/W |
| Tim SATOR | ✅ R/W | ✅ R/W | ✅ R/W | ✅ R/W |
| Global | ✅ R/W | ✅ R/W | ✅ R/W | ✅ R/W |
| Private | ✅ R/W | ✅ R/W | ✅ R/W | ✅ R/W |
| Announcement | Read | Read | ✅ R/W | ✅ R/W |

---

## 🗃️ DATABASE SCHEMA

```sql
-- Chat Rooms
CREATE TABLE chat_rooms (
  id SERIAL PRIMARY KEY,
  room_type VARCHAR(20) NOT NULL, 
    -- 'toko', 'tim', 'global', 'private', 'announcement'
  
  -- Context (depends on type)
  toko_id INTEGER REFERENCES toko(id), -- for 'toko' type
  sator_id INTEGER REFERENCES users(id), -- for 'tim' type
  
  -- For private chat
  user1_id INTEGER REFERENCES users(id),
  user2_id INTEGER REFERENCES users(id),
  
  name VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Chat Members
CREATE TABLE chat_members (
  id SERIAL PRIMARY KEY,
  room_id INTEGER REFERENCES chat_rooms(id),
  user_id INTEGER REFERENCES users(id),
  
  is_muted BOOLEAN DEFAULT false,
  last_read_at TIMESTAMP,
  
  UNIQUE(room_id, user_id)
);

-- Messages
CREATE TABLE chat_messages (
  id SERIAL PRIMARY KEY,
  room_id INTEGER REFERENCES chat_rooms(id),
  sender_id INTEGER REFERENCES users(id),
  
  message_type VARCHAR(20) DEFAULT 'text', -- 'text', 'image'
  content TEXT,
  image_url TEXT,
  
  -- Mention
  mentions INTEGER[], -- array of user_ids
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  -- For auto-delete
  expires_at TIMESTAMP -- default: created_at + 1 month
);

-- Read Receipts
CREATE TABLE message_reads (
  id SERIAL PRIMARY KEY,
  message_id INTEGER REFERENCES chat_messages(id),
  user_id INTEGER REFERENCES users(id),
  read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  
  UNIQUE(message_id, user_id)
);

-- Indexes
CREATE INDEX idx_messages_room ON chat_messages(room_id, created_at DESC);
CREATE INDEX idx_messages_expires ON chat_messages(expires_at);
```

---

## 🔧 TECHNICAL IMPLEMENTATION

```
Technology:
├─ Supabase Realtime (websocket for live chat)
├─ Supabase Database (message storage)
├─ Firebase Cloud Messaging (push notification)
├─ Cloudinary (image upload)

Flow:
1. User sends message
2. Insert to chat_messages
3. Supabase trigger → Realtime broadcast
4. Other users receive instantly
5. FCM push notification to offline users
6. Update read receipts on view

Cleanup:
- Daily cron job
- Delete messages where expires_at < NOW()
- Keep announcement 6 months
```

---

## 📱 UI FLOW

### **Chat List (Home)**
```
┌─────────────────────────────────────────┐
│ 💬 CHAT                                 │
├─────────────────────────────────────────┤
│                                         │
│ 📢 ANNOUNCEMENT              • 1 new    │
│    "Target bulan ini naik..."           │
│                                         │
│ ─────────────────────────────────────  │
│                                         │
│ 🏪 TOKO                                 │
│ ├─ Transmart MTC            • 3 new     │
│ ├─ Panakukkang                          │
│ └─ Mall Ratu                • 1 new     │
│                                         │
│ ─────────────────────────────────────  │
│                                         │
│ 👥 TIM                                  │
│ ├─ Tim Nio                  • 5 new     │
│ └─ Global Team                          │
│                                         │
│ ─────────────────────────────────────  │
│                                         │
│ 💬 PRIVATE                              │
│ ├─ Ahmad                    • 2 new     │
│ └─ SATOR Nio                            │
│                                         │
└─────────────────────────────────────────┘
```

---

## ✅ SUMMARY

| Feature | Status |
|---------|--------|
| Chat per Toko + Data | ✅ |
| Chat Tim SATOR | ✅ |
| Chat Global | ✅ |
| Private 1-on-1 | ✅ |
| Announcement (SPV only) | ✅ |
| Push Notification | ✅ |
| Mention (@nama) | ✅ |
| Read Receipts | ✅ |
| Send Photo/Image | ✅ |
| History 1 month | ✅ |
| File attachment | ❌ Not needed |

---

**Status:** Built-in Chat System - 100% PLANNED ✅
