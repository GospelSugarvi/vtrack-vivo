# Design System: SPC Group Recommendations

## Problem Statement
- Toko SPC adalah grup toko (chain store)
- Order dilakukan 1 pintu untuk semua cabang SPC
- Perlu rekomendasi gabungan untuk semua toko SPC sekaligus
- Sistem harus tetap ringan dan tidak merusak yang sudah ada

## Current System Analysis

### Existing Tables:
1. **stores** - Data toko (store_name, area, grade)
2. **store_inventory** - Stok per toko per variant
3. **stock_rules** - Min qty per grade
4. **assignments_sator_store** - Toko yang di-handle Sator

### Existing Functions:
1. `get_store_stock_status(sator_id)` - List toko dengan status
2. `get_store_recommendations(store_id)` - Rekomendasi per toko

## Proposed Solutions (3 Options)

### OPTION 1: Pattern Matching (RECOMMENDED - PALING RINGAN)
**Cara:** Deteksi grup berdasarkan prefix nama toko (ILIKE 'SPC%')

**Pros:**
- ✅ Tidak perlu ubah struktur tabel
- ✅ Query ringan (hanya WHERE clause)
- ✅ Fleksibel untuk grup lain (Giant%, Transmart%, dll)
- ✅ Tidak ada migration kompleks

**Cons:**
- ❌ Bergantung pada naming convention
- ❌ Jika nama toko berubah, perlu update

**Implementation:**
```sql
-- Aggregate stok semua toko SPC
SELECT 
    variant_id,
    SUM(quantity) as total_stock_all_spc,
    COUNT(DISTINCT store_id) as total_spc_stores
FROM store_inventory si
JOIN stores s ON si.store_id = s.id
WHERE s.store_name ILIKE 'SPC%'
  AND s.status = 'active'
GROUP BY variant_id
```

**Performance:** O(n) - Scan store_inventory dengan filter, lalu GROUP BY

---

### OPTION 2: Add store_group Column
**Cara:** Tambah kolom `store_group` di tabel stores

**Pros:**
- ✅ Lebih eksplisit dan maintainable
- ✅ Bisa untuk berbagai grup
- ✅ Query lebih cepat dengan index

**Cons:**
- ❌ Perlu migration (ALTER TABLE)
- ❌ Perlu update data existing
- ❌ Perlu maintain kolom baru

**Implementation:**
```sql
ALTER TABLE stores ADD COLUMN store_group TEXT;
CREATE INDEX idx_stores_group ON stores(store_group);

UPDATE stores SET store_group = 'SPC' WHERE store_name ILIKE 'SPC%';
```

---

### OPTION 3: Create store_groups Table (OVERKILL)
**Cara:** Buat tabel relasi many-to-many

**Pros:**
- ✅ Paling fleksibel (1 toko bisa di banyak grup)
- ✅ Normalized database design

**Cons:**
- ❌ Terlalu kompleks untuk use case ini
- ❌ Perlu JOIN tambahan (lebih lambat)
- ❌ Overhead maintenance

---

## RECOMMENDATION: OPTION 1 (Pattern Matching)

### Why?
1. **Simplicity** - Tidak perlu ubah struktur database
2. **Performance** - Query tetap ringan dengan proper indexing
3. **Flexibility** - Bisa langsung support grup lain
4. **Zero Migration Risk** - Tidak ada ALTER TABLE

### Query Strategy (Optimized):

```sql
-- Efficient aggregation dengan CTE
WITH spc_stores AS (
  SELECT id 
  FROM stores 
  WHERE store_name ILIKE 'SPC%' 
    AND status = 'active'
),
spc_inventory AS (
  SELECT 
    si.variant_id,
    SUM(si.quantity) as total_qty,
    COUNT(DISTINCT si.store_id) as store_count
  FROM store_inventory si
  WHERE si.store_id IN (SELECT id FROM spc_stores)
  GROUP BY si.variant_id
)
SELECT 
  p.model_name,
  pv.ram_rom,
  pv.color,
  si.total_qty,
  si.store_count,
  -- Min stock = min_qty * jumlah toko SPC
  (COALESCE(sr.min_qty, 3) * si.store_count) as total_min_stock,
  GREATEST(
    (COALESCE(sr.min_qty, 3) * si.store_count) - si.total_qty,
    0
  ) as order_qty
FROM products p
JOIN product_variants pv ON pv.product_id = p.id
LEFT JOIN spc_inventory si ON si.variant_id = pv.id
LEFT JOIN stock_rules sr ON sr.product_id = p.id AND sr.grade = 'A' -- Assume SPC grade A
WHERE p.status = 'active' AND pv.active = true;
```

**Performance Analysis:**
- CTE `spc_stores`: Fast (indexed on store_name pattern)
- CTE `spc_inventory`: Aggregate only SPC stores
- Main query: JOIN with aggregated data (not per-store)
- **Estimated time:** < 100ms for 1000 products x 10 SPC stores

### Required Index (if not exists):
```sql
CREATE INDEX IF NOT EXISTS idx_stores_name_pattern ON stores(store_name text_pattern_ops);
CREATE INDEX IF NOT EXISTS idx_store_inventory_store_variant ON store_inventory(store_id, variant_id);
```

---

## Implementation Plan

### Phase 1: Database (SQL)
1. ✅ Create function `get_spc_group_recommendations(p_sator_id UUID)`
2. ✅ Add indexes for performance
3. ✅ Test with sample data

### Phase 2: Flutter (UI)
1. ✅ Add "Grup SPC" button in ListTokoPage (conditional)
2. ✅ Create SpcGroupRecommendationPage
3. ✅ Show aggregated recommendations

### Phase 3: Testing
1. ✅ Test performance with real data
2. ✅ Verify calculations
3. ✅ User acceptance testing

---

## Questions for User:

1. **Apakah semua toko SPC punya grade yang sama?** (untuk stock_rules)
2. **Apakah ada grup toko lain selain SPC?** (Giant, Transmart, dll)
3. **Berapa jumlah toko SPC saat ini?** (untuk estimasi performance)
4. **Apakah naming convention "SPC xxx" konsisten?** (SPC Kupang, SPC Atambua, dll)

---

## Next Steps:

**Tolong jalankan query ini dulu Om:**
```
supabase/check_spc_stores_structure.sql
```

Saya perlu tahu:
- Struktur tabel stores lengkap
- Jumlah dan nama toko SPC yang ada
- Apakah ada kolom grouping yang sudah ada

Setelah itu saya bisa buat implementasi yang paling optimal! 🚀
