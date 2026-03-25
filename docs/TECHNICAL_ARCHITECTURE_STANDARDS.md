# 🏗️ TECHNICAL ARCHITECTURE & STANDARDS
**Date:** 8 Januari 2026  
**Status:** 100% LOCKED ✅

---

## 🎯 PHILOSOPHY

```
"Aplikasi internal yang stabil, sederhana, dan aman
 lebih bernilai daripada aplikasi canggih yang rapuh."

- Kode sederhana, mudah maintain
- Error = STOP, FIX, baru LANJUT
- Tidak asumsi, selalu tanya
- Tidak quick fix yang merusak
- Sesuai engineering standards
```

---

## 🏛️ ARCHITECTURE

```
┌─────────────────────────────────────────────────────────┐
│                    FLUTTER APP                          │
│                   (1 Codebase)                          │
│  ├─ Android: APK (Play Store / Direct)                  │
│  └─ iOS: PWA (Vercel)                                  │
└────────────────────────┬────────────────────────────────┘
                         │ HTTPS
                         ▼
┌─────────────────────────────────────────────────────────┐
│              SUPABASE EDGE FUNCTIONS                    │
│  ├─ Stateless                                          │
│  ├─ Idempotent                                         │
│  ├─ Validation layer                                   │
│  └─ Business logic (light)                             │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              SUPABASE POSTGRESQL                        │
│  ├─ Source of truth                                    │
│  ├─ Transactions                                       │
│  ├─ Constraints (unique, foreign key, check)           │
│  ├─ Row Level Security (RLS)                           │
│  ├─ Triggers & Functions (calculation)                 │
│  └─ Audit logging                                      │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              SUPPORTING SERVICES (FREE)                 │
│  ├─ Cloudinary: Image storage                          │
│  ├─ Firebase FCM: Push notifications                   │
│  └─ Vercel: PWA hosting                                │
└─────────────────────────────────────────────────────────┘
```

---

## 🔒 GOLDEN RULES

### **A. Frontend Tidak Dipercaya**
```
❌ Client menghitung bonus → kirim hasil
✅ Client kirim data penjualan → Server hitung bonus

❌ Client set status "approved"
✅ Client kirim request → Server validasi → Server set status

UI hanya kirim NIAT, semua keputusan di BACKEND/DB.
```

### **B. Database Adalah Sumber Kebenaran**
```
Semua data penting:
├─ Hitung di database (trigger/function)
├─ Validasi final di database (constraint)
├─ Status final di database
└─ Tidak ada "kira-kira" di client

Contoh:
├─ Bonus = calculated by DB trigger
├─ Achievement = calculated by DB view
├─ Stock count = aggregated by DB
└─ IMEI unique = enforced by DB constraint
```

### **C. Transaction untuk Write Penting**
```
Semua operasi yang melibatkan:
├─ Multiple table updates
├─ Calculation + insert
├─ Financial data
└─ Status changes

WAJIB pakai TRANSACTION:
├─ Berhasil semua = COMMIT
├─ Gagal 1 = ROLLBACK semua
└─ Tidak ada state setengah jadi
```

### **D. Gagal Total Lebih Baik dari Setengah**
```
❌ Insert berhasil, tapi bonus gagal hitung → data kacau
✅ Kalau bonus gagal → seluruh transaksi rollback → user coba lagi

Sistem harus dalam keadaan VALID atau TIDAK BERUBAH.
Tidak boleh ada keadaan "setengah jalan".
```

---

## 📝 EDGE FUNCTION RULES

```
1. STATELESS
   └─ Tidak simpan state antar request
   └─ Setiap request independen

2. IDEMPOTENT
   └─ Aman dipanggil 2x dengan data sama
   └─ Hasil tetap sama, tidak double insert
   └─ Pakai idempotency key kalau perlu

3. VALIDATION
   └─ Validasi semua input
   └─ Reject invalid data dengan error jelas
   └─ Tidak teruskan data jelek ke DB

4. ERROR HANDLING
   └─ Try-catch semua
   └─ Log error ke audit table
   └─ Return error message yang jelas
   └─ Tidak hide error

5. SIMPLE & FOKUS
   └─ 1 function = 1 purpose
   └─ Tidak campur banyak logic
   └─ Mudah debug
```

---

## 🗄️ DATABASE RULES

### **Constraint (Wajib)**
```sql
-- Unique constraint
UNIQUE(imei)  -- IMEI tidak boleh duplikat
UNIQUE(toko_id, produk_id, tanggal)  -- Laporan harian 1x per toko

-- Foreign key
REFERENCES users(id) ON DELETE RESTRICT  -- Tidak boleh hapus user yang punya data

-- Check constraint
CHECK(harga > 0)  -- Harga harus positif
CHECK(qty >= 0)  -- Quantity tidak boleh minus
```

### **Transaction (Wajib untuk Write)**
```sql
BEGIN;
  INSERT INTO sales (...) VALUES (...);
  UPDATE stock SET qty = qty - 1 WHERE ...;
  INSERT INTO bonus_log (...) VALUES (...);
COMMIT;

-- Kalau ada yang gagal → otomatis ROLLBACK
```

### **Row Level Security (RLS)**
```sql
-- Promotor hanya lihat data sendiri
CREATE POLICY promotor_policy ON sales
  FOR ALL USING (user_id = auth.uid());

-- SATOR lihat data promotor bawahan
CREATE POLICY sator_policy ON sales
  FOR SELECT USING (
    user_id IN (SELECT id FROM users WHERE sator_id = auth.uid())
  );
```

### **Audit Log**
```sql
CREATE TABLE audit_log (
  id SERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  action TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
  old_data JSONB,
  new_data JSONB,
  changed_by UUID REFERENCES users(id),
  changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger on every important table
```

---

## 🛡️ ERROR HANDLING STRATEGY

### **3 Layer Defense**
```
LAYER 1: CLIENT
├─ Input validation (format, required)
├─ Disable button after click
├─ Show loading state
└─ First line defense (UX)

LAYER 2: EDGE FUNCTION
├─ Validate all input again
├─ Check business rules
├─ Return clear error if invalid
└─ Second line defense (logic)

LAYER 3: DATABASE
├─ Constraint violation = reject
├─ Transaction = rollback on error
├─ Trigger validation = final check
└─ Final line defense (data integrity)
```

### **Error Response**
```json
// WRONG - vague error
{ "error": "Something went wrong" }

// CORRECT - specific error
{
  "error": true,
  "code": "IMEI_DUPLICATE",
  "message": "IMEI sudah terdaftar di sistem",
  "field": "imei"
}
```

### **Error Logging**
```
Setiap error WAJIB di-log:
├─ Timestamp
├─ User ID
├─ Endpoint
├─ Request data (sanitized)
├─ Error message
├─ Stack trace (kalau ada)

Log ini untuk DEBUG, bukan di-hide.
```

---

## 🔄 FAILURE RECOVERY

| Failure Type | Prevention | Recovery |
|--------------|------------|----------|
| Network error | Retry + queue | Auto resend when online |
| Double submit | Idempotency key + unique | Reject duplicate |
| Invalid data | 3-layer validation | Reject with message |
| Calculation error | DB trigger/function | Recalculate on fix |
| Race condition | Transaction + lock | Rollback + retry |
| Service down | Graceful degradation | Queue + retry later |
| DB corruption | Daily backup | Restore from backup |
| Admin mistake | Soft delete + audit | Restore from audit |

---

## 📊 ADMIN CONTROL

```
SEMUA ATURAN BISNIS DI DATABASE:
├─ Bonus ranges → admin_bonus_config table
├─ 2:1 products → admin_special_products table
├─ Feature flags → admin_feature_flags table
├─ Target rules → admin_target_config table
└─ System config → admin_system_config table

TIDAK ADA HARDCODE:
❌ if (product == "Y02") bonus = 5000
✅ SELECT bonus FROM bonus_config WHERE product_id = ?

Admin bisa ubah TANPA deploy.
```

---

## 🧪 TESTING REQUIREMENTS

```
Sebelum deploy WAJIB test:

1. UNIT TEST
   └─ Setiap function/service
   
2. INTEGRATION TEST
   └─ Edge function ↔ Database
   
3. ERROR CASE TEST
   └─ Invalid input
   └─ Network failure
   └─ Duplicate data
   
4. RESTORE TEST
   └─ Backup restore works
```

---

## 📋 GO-LIVE CHECKLIST

```
[ ] Semua write pakai transaction
[ ] Kolom penting punya unique constraint
[ ] RLS aktif untuk semua table
[ ] Edge Function ada error handling
[ ] Audit log berjalan
[ ] Feature flag bisa matikan fitur
[ ] Backup aktif & pernah di-test restore
[ ] Error tercatat & bisa dilihat
[ ] Admin bisa control semua config

Jika satu saja ❌ → TUNDA DEPLOY
```

---

## 🚫 YANG TIDAK KITA PAKAI

```
❌ Microservice (over-engineering untuk skala ini)
❌ Message broker (tidak perlu)
❌ Complex caching (Supabase sudah cukup)
❌ Eventual consistency (kita butuh strong consistency)
❌ Over-scaling (35-50 user tidak butuh)
❌ Quick fix yang hide error
❌ Asumsi tanpa konfirmasi
```

---

## ✅ SUMMARY

| Aspect | Standard |
|--------|----------|
| Architecture | Simple, 3-tier |
| Frontend | UI only, no business logic |
| Backend | Stateless, idempotent |
| Database | Source of truth, constraints |
| Validation | 3-layer defense |
| Error | Log, tidak hide |
| Transaction | Wajib untuk write |
| Admin | Control via database |
| Backup | Daily + tested restore |
| Deployment | Checklist wajib lulus |

---

**Status:** Technical Architecture & Standards - 100% LOCKED ✅
