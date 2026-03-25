# 💰 Bonus Calculation Logic

## 🎯 Overview
Sistem bonus menggunakan **2-tier priority system**:
1. **PRIORITY 1**: Flat Bonus (Produk khusus yang ditentukan admin)
2. **PRIORITY 2**: Range Bonus (Berdasarkan harga, untuk produk yang belum ditentukan)

---

## 📋 Logic Flow

```
┌─────────────────────────────────────────────────────────────┐
│ PROMOTOR JUAL PRODUK                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 1: Cek Promotor Type                                   │
│ ├─ Official → Pakai bonus_official                          │
│ └─ Training → Pakai bonus_training                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2: PRIORITY 1 - Cek Flat Bonus (Produk Khusus)        │
│                                                             │
│ Query: SELECT bonus FROM bonus_rules                        │
│        WHERE bonus_type = 'flat'                            │
│        AND product_id = [product_id]                        │
│                                                             │
│ ├─ FOUND & bonus > 0 → PAKAI BONUS INI ✅                  │
│ ├─ FOUND & bonus = 0 → PAKAI 0 (admin sengaja set 0) ✅    │
│ └─ NOT FOUND → Lanjut ke STEP 3 ⬇️                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3: PRIORITY 2 - Cek Range Bonus (Berdasarkan Harga)   │
│                                                             │
│ Query: SELECT bonus FROM bonus_rules                        │
│        WHERE bonus_type = 'range'                           │
│        AND price >= min_price                               │
│        AND price < max_price                                │
│                                                             │
│ ├─ FOUND → PAKAI BONUS INI ✅                              │
│ └─ NOT FOUND → Bonus = 0 ⚠️                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ RESULT: estimated_bonus disimpan ke sales_sell_out         │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔍 Examples

### **Example 1: Produk dengan Flat Bonus (X-Series)**

**Setup di Admin:**
```
Flat Bonus:
├─ X200 Pro → Official: Rp 100.000, Training: Rp 90.000
└─ X200 → Official: Rp 80.000, Training: Rp 72.000

Range Bonus:
├─ 6-8 juta → Official: Rp 90.000, Training: Rp 80.000
└─ 8-10 juta → Official: Rp 120.000, Training: Rp 108.000
```

**Scenario:**
- Promotor Official jual X200 Pro (harga: Rp 7.500.000)

**Calculation:**
1. Cek promotor type: **Official** ✅
2. Cek flat bonus untuk X200 Pro: **FOUND** → Rp 100.000 ✅
3. **STOP** (tidak cek range bonus)

**Result:** Bonus = **Rp 100.000** (dari flat bonus, bukan Rp 90.000 dari range)

---

### **Example 2: Produk tanpa Flat Bonus (Y-Series)**

**Setup di Admin:**
```
Flat Bonus:
├─ (Y-Series tidak ada di flat bonus)

Range Bonus:
├─ 2-3 juta → Official: Rp 25.000, Training: Rp 22.500
└─ 3-4 juta → Official: Rp 45.000, Training: Rp 40.000
```

**Scenario:**
- Promotor Official jual Y400 (harga: Rp 3.200.000)

**Calculation:**
1. Cek promotor type: **Official** ✅
2. Cek flat bonus untuk Y400: **NOT FOUND** ❌
3. Cek range bonus untuk Rp 3.200.000: **FOUND** (3-4 juta) → Rp 45.000 ✅

**Result:** Bonus = **Rp 45.000** (dari range bonus)

---

### **Example 3: Admin Set Flat Bonus = 0 (Intentional)**

**Setup di Admin:**
```
Flat Bonus:
├─ Demo Unit Y21D → Official: Rp 0, Training: Rp 0

Range Bonus:
├─ 1-2 juta → Official: Rp 15.000, Training: Rp 13.500
```

**Scenario:**
- Promotor Official jual Demo Unit Y21D (harga: Rp 1.500.000)

**Calculation:**
1. Cek promotor type: **Official** ✅
2. Cek flat bonus untuk Demo Unit Y21D: **FOUND** → Rp 0 ✅
3. **STOP** (tidak cek range bonus, karena admin sengaja set 0)

**Result:** Bonus = **Rp 0** (admin intentionally set no bonus for demo units)

---

### **Example 4: Produk Baru, Belum Ada Rule**

**Setup di Admin:**
```
Flat Bonus:
├─ (Produk baru belum ditambahkan)

Range Bonus:
├─ 2-3 juta → Official: Rp 25.000
├─ 3-4 juta → Official: Rp 45.000
└─ (Tidak ada range untuk > 10 juta)
```

**Scenario:**
- Promotor Official jual Produk Baru (harga: Rp 12.000.000)

**Calculation:**
1. Cek promotor type: **Official** ✅
2. Cek flat bonus: **NOT FOUND** ❌
3. Cek range bonus untuk Rp 12.000.000: **NOT FOUND** ❌

**Result:** Bonus = **Rp 0** ⚠️

**Action:** Admin harus tambah range bonus untuk harga > 10 juta

---

## 🎛️ Admin Control

### **Kapan Pakai Flat Bonus?**
✅ Produk khusus dengan bonus tetap (X-Series, iQOO, dll)
✅ Produk promo dengan bonus spesial
✅ Demo unit yang tidak dapat bonus (set = 0)
✅ Produk dengan bonus berbeda dari range normalnya

### **Kapan Pakai Range Bonus?**
✅ Produk umum (Y-Series, V-Series)
✅ Produk baru yang belum ditentukan bonus khusus
✅ Default fallback untuk semua produk

### **Cara Kerja di Admin UI:**

**Admin Bonus Page:**
```
Tab 1: Range Bonus (Default untuk semua)
├─ 0 - 2 juta: Rp 0 / Rp 0
├─ 2 - 4 juta: Rp 25.000 / Rp 22.500
├─ 4 - 6 juta: Rp 45.000 / Rp 40.000
└─ 6+ juta: Rp 90.000 / Rp 80.000

Tab 2: Flat Bonus (Produk Khusus)
├─ X200 Pro: Rp 100.000 / Rp 90.000
├─ X200: Rp 80.000 / Rp 72.000
├─ iQOO Z9: Rp 70.000 / Rp 63.000
└─ Demo Y21D: Rp 0 / Rp 0

Tab 3: Ratio 2:1 (Special Calculation)
├─ (Future feature)
```

---

## ⚙️ Technical Implementation

### **Database Table: bonus_rules**
```sql
CREATE TABLE bonus_rules (
  id uuid PRIMARY KEY,
  bonus_type text CHECK (bonus_type IN ('range', 'flat', 'ratio')),
  
  -- For range-based
  min_price numeric,
  max_price numeric,
  
  -- For flat bonus
  product_id uuid REFERENCES products(id),
  ram int,
  storage int,
  
  -- Bonus amounts
  bonus_official numeric,
  bonus_training numeric,
  flat_bonus numeric,  -- Legacy column
  ratio_value int,     -- For ratio type
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

### **Trigger Function:**
```sql
CREATE OR REPLACE FUNCTION process_sell_out_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_bonus NUMERIC := 0;
  v_promotor_type TEXT;
  v_product_id UUID;
BEGIN
  -- Get promotor type
  SELECT COALESCE(promotor_type, 'official') INTO v_promotor_type
  FROM users WHERE id = NEW.promotor_id;
  
  -- Get product_id
  SELECT p.id INTO v_product_id 
  FROM products p
  JOIN product_variants pv ON p.id = pv.product_id
  WHERE pv.id = NEW.variant_id;
  
  -- PRIORITY 1: Flat bonus
  SELECT 
    CASE 
      WHEN v_promotor_type = 'official' THEN COALESCE(bonus_official, flat_bonus)
      ELSE COALESCE(bonus_training, flat_bonus)
    END
  INTO v_bonus
  FROM bonus_rules
  WHERE bonus_type = 'flat' AND product_id = v_product_id
  LIMIT 1;
  
  -- PRIORITY 2: Range bonus (if flat not found)
  IF NOT FOUND OR v_bonus IS NULL THEN
    SELECT 
      CASE 
        WHEN v_promotor_type = 'official' THEN bonus_official
        ELSE bonus_training
      END
    INTO v_bonus
    FROM bonus_rules
    WHERE bonus_type = 'range'
    AND NEW.price_at_transaction >= min_price
    AND NEW.price_at_transaction < COALESCE(max_price, 999999999)
    LIMIT 1;
  END IF;
  
  -- Default to 0
  v_bonus := COALESCE(v_bonus, 0);
  NEW.estimated_bonus := v_bonus;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## ✅ Summary

| Scenario | Flat Bonus | Range Bonus | Result |
|----------|------------|-------------|--------|
| Produk ada di flat, bonus > 0 | ✅ FOUND | ⏭️ SKIP | Use flat bonus |
| Produk ada di flat, bonus = 0 | ✅ FOUND | ⏭️ SKIP | Use 0 (intentional) |
| Produk tidak ada di flat | ❌ NOT FOUND | ✅ CHECK | Use range bonus |
| Tidak ada di flat & range | ❌ NOT FOUND | ❌ NOT FOUND | Bonus = 0 |

**Key Point:** 
- Flat bonus = **OVERRIDE** (prioritas tertinggi)
- Range bonus = **FALLBACK** (default untuk semua)
- Bonus = 0 bisa intentional (admin set) atau tidak ada rule

---

**Status:** Bonus Calculation Logic - 100% DOCUMENTED ✅
