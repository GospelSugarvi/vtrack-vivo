# PERMISSION & ACCESS SYSTEM (RLS + PRODUCT)
**Status:** DRAFT
**Date:** 14 January 2026

---

## 🔐 ROW LEVEL SECURITY (RLS) STRATEGY

Sistem menggunakan Supabase RLS untuk keamanan data level database. Aplikasi frontend hanya akan menerima data yang diizinkan oleh RLS.

### **1. USER HIERARCHY & ASSIGNMENT**

Tabel `user_assignments` (atau hierarchy tables terpisah) akan menjadi kunci validasi akses.

| Level | Table Relation | Logic Access |
|-------|----------------|--------------|
| **Promotor** | `promotors` | View data where `user_id = auth.uid()` |
| **SATOR** | `sator_promotors` | View data where `promotor_id` IN (my_assigned_promotors) |
| **SPV** | `spv_sators` | View data where `sator_id` IN (my_assigned_sators) |
| **Manager** | `manager_spvs` | View data where `spv_id` IN (my_assigned_spvs) |
| **Admin** | `users.role = 'admin'` | View ALL data |

---

### **2. DATA VISIBILITY MATRIX**

| Data Object | Promotor | SATOR | SPV | Manager | Admin |
|-------------|----------|-------|-----|---------|-------|
| **Sell Out** | Own Only | Team Detail | Area Detail | Macro Detail | All |
| **Sell In** | Own Store | Team Stores | Area Stores | Macro Stores | All |
| **Stock** | Own Store | Team Stores | Area Stores | Macro Stores | All |
| **Bonus** | Own Only | Own Only | Own Only | N/A | View All |
| **Targets** | Own Only | Team Targets | Area Targets | Macro Targets | CRUD |
| **Customers** | Own Input | Team Input | Area Input | Macro Input | All |

**Catatan Khusus:**
- **Bonus Privacy:** SATOR tidak boleh lihat rincian Gaji Pokok Promotor (kecuali Admin/HR). SATOR hanya lihat performance.
- **Cross-Access:** SATOR A tidak bisa melihat data tim SATOR B.

---

### **3. FEATURE PERMISSIONS (App Logic)**

Selain data access, ada logic feature access (Menu Visibility).

| Feature | Promotor | SATOR | SPV | Manager | Admin |
|---------|----------|-------|-----|---------|-------|
| **Input Jual** | ✅ | ❌ | ❌ | ❌ | ✅ (Override) |
| **Input Stok** | ✅ | ✅ (Bantu) | ❌ | ❌ | ✅ |
| **Approve Stok** | ❌ | ✅ | ✅ | ❌ | ✅ |
| **Edit Target** | ❌ | ❌ | ❌ | ❌ | ✅ |
| **User Mgmt** | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Broadcast** | ❌ | ✅ (To Team) | ✅ (To Area) | ✅ (To All) | ✅ |

---

## 📦 PRODUCT MANAGEMENT SYSTEM

Admin memiliki kontrol penuh terhadap master data produk untuk mengakomodasi dinamika pasar.

### **1. PRODUCT ATTRIBUTES**

| Field | Tipe | Deskripsi |
|-------|------|-----------|
| `id` | UUID | Primary Key |
| `model_name` | String | e.g. "Y29 4G" |
| `series` | Enum | Y-Series, V-Series, X-Series |
| `srp` | Number | Harga resmi saat ini |
| `image_url` | String | Cloudinary URL |
| `status` | Enum | Active, EOL (End of Life), Coming Soon |
| `release_date` | Date | Tanggal rilis |

### **2. DYNAMIC FLAGS (Business Logic)**

Admin bisa set flag ini untuk mengubah perilaku sistem tanpa coding.

| Flag | Fungsi | Benefit |
|------|--------|---------|
| `is_focus` | Menentukan masuk target "Tipe Fokus" | Bisa ganti produk fokus tiap bulan |
| `is_npo` | New Product Order (Barang baru) | Tracking khusus launching |
| `bonus_type` | `range` / `flat` / `ratio` | Menentukan rumus bonus promotor |
| `ratio_val` | integer (default: 1) | Jika 2, maka hitung 2 unit = 1 bonus |
| `flat_bonus` | number | Jika type flat, pakai nilai ini |

### **3. VARIANT MANAGEMENT**

Satu model HP bisa punya banyak varian memori & warna.

```
Model: Y29 4G
├─ Varian 1: 4GB/128GB (Rp 2.099.000)
│  ├─ Warna: Hitam
│  └─ Warna: Ungu
├─ Varian 2: 6GB/128GB (Rp 2.399.000)
│  ├─ Warna: Hitam
│  └─ Warna: Hijau
```

**Stok Level:** Tracking stok dilakukan sampai level **Model + Varian + Warna** (SKU Level).

---

### **4. PRICE HISTORY (Audit Trail)**

Jika harga berubah, sistem mencatat history untuk perhitungan bonus yang akurat.

`product_price_history`:
- `product_id`
- `old_price`
- `new_price`
- `effective_date`
- `changed_by` (Admin ID)

**Logic Bonus:** Bonus dihitung berdasarkan harga **saat transaksi terjadi**, bukan harga saat ini.

---

### **5. ADMIN UI FOR PRODUCT**

1. **Product List:** Filter by Series, Status, Focus.
2. **Bulk Action:** Set Fokus Massal, Set Price Change Massal.
3. **Detail Editor:** Edit flags, upload image, manage variants.

---

**CONFIRMATION:**
Apakah strategi permissions dan product management ini sudah sesuai?
Jika ya, kita akan lock document ini.
