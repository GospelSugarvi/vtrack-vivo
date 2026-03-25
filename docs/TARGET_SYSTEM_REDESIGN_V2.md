# 🎯 TARGET SYSTEM REDESIGN V2 - EASY TO USE
**Date:** 24 Januari 2026  
**Problem:** Sistem sekarang ribet untuk 100 orang

---

## ❌ MASALAH SISTEM SEKARANG

### 1. Terlalu Manual
- Harus expand 1-1 user card
- Isi form 1-1
- Klik simpan 1-1
- **100 orang = 100x klik expand + isi + simpan**

### 2. Tidak Terorganisir
- Semua role campur jadi satu
- Susah cari promotor tertentu
- Tidak ada grouping per SATOR

### 3. Lambat
- Load semua user sekaligus
- Berat kalau banyak data

---

## ✅ SOLUSI BARU - 3 TAB SYSTEM

### **TAB 1: PROMOTOR (Group by SATOR)**
```
┌─────────────────────────────────────────────────────┐
│ [Promotor] [SATOR] [SPV]                            │
├─────────────────────────────────────────────────────┤
│                                                     │
│ 📊 BULK SET TARGET                                  │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Target Sell Out: [10.000.000]                   │ │
│ │ Target Fokus:    [30]                           │ │
│ │ [Apply to All Promotor] [Apply to Selected]    │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ 🔍 Filter by SATOR: [Semua ▼]                      │
│                                                     │
│ ┌─ SATOR: BUDI ─────────────────────────────────┐  │
│ │ [✓] Ahmad    | 10.000.000 | 30 | [Edit]      │  │
│ │ [✓] Citra    | 10.000.000 | 30 | [Edit]      │  │
│ │ [✓] Dedi     | 10.000.000 | 30 | [Edit]      │  │
│ │                                                │  │
│ │ [Set Target for Selected (3)]                 │  │
│ └───────────────────────────────────────────────┘  │
│                                                     │
│ ┌─ SATOR: EKA ──────────────────────────────────┐  │
│ │ [✓] Fani     | 10.000.000 | 30 | [Edit]      │  │
│ │ [✓] Gita     | 10.000.000 | 30 | [Edit]      │  │
│ │                                                │  │
│ │ [Set Target for Selected (2)]                 │  │
│ └───────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Features:**
- ✅ Group by SATOR (mudah manage per team)
- ✅ Bulk set (1x klik untuk semua)
- ✅ Checkbox select (pilih beberapa sekaligus)
- ✅ Inline edit (langsung edit di table)
- ✅ Filter by SATOR

---

### **TAB 2: SATOR**
```
┌─────────────────────────────────────────────────────┐
│ [Promotor] [SATOR] [SPV]                            │
├─────────────────────────────────────────────────────┤
│                                                     │
│ 📊 BULK SET TARGET                                  │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Target Sell In:  [50.000.000]                   │ │
│ │ Target Sell Out: [100.000.000]                  │ │
│ │ [Apply to All SATOR] [Apply to Selected]       │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ 🔍 Filter by SPV: [Semua ▼]                        │
│                                                     │
│ ┌─ SPV: HENDRA ─────────────────────────────────┐  │
│ │ [✓] SATOR Budi | 50jt | 100jt | [Edit]        │  │
│ │ [✓] SATOR Eka  | 50jt | 100jt | [Edit]        │  │
│ │                                                │  │
│ │ [Set Target for Selected (2)]                 │  │
│ └───────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

### **TAB 3: SPV**
```
┌─────────────────────────────────────────────────────┐
│ [Promotor] [SATOR] [SPV]                            │
├─────────────────────────────────────────────────────┤
│                                                     │
│ 📊 BULK SET TARGET                                  │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Target Sell In:  [200.000.000]                  │ │
│ │ Target Sell Out: [500.000.000]                  │ │
│ │ [Apply to All SPV] [Apply to Selected]         │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ [✓] SPV Hendra | 200jt | 500jt | [Edit]           │
│ [✓] SPV Indra  | 200jt | 500jt | [Edit]           │
│                                                     │
│ [Set Target for Selected (2)]                      │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 🚀 WORKFLOW BARU

### Scenario 1: Set Target untuk 100 Promotor (SAMA SEMUA)
```
1. Pilih tab "Promotor"
2. Isi Bulk Set Target:
   - Sell Out: 10.000.000
   - Fokus: 30
3. Klik "Apply to All Promotor"
4. DONE! (1 menit untuk 100 orang)
```

### Scenario 2: Set Target per Team SATOR
```
1. Pilih tab "Promotor"
2. Filter by SATOR: "Budi"
3. Isi Bulk Set Target:
   - Sell Out: 15.000.000
   - Fokus: 40
4. Centang semua promotor Budi
5. Klik "Set Target for Selected"
6. DONE! (30 detik untuk 1 team)
```

### Scenario 3: Edit Individual
```
1. Pilih tab "Promotor"
2. Cari promotor "Ahmad"
3. Klik "Edit" di row Ahmad
4. Ubah target
5. Auto-save
6. DONE! (10 detik)
```

---

## 📊 TABLE VIEW (Inline Edit)

```
┌──────────────────────────────────────────────────────────┐
│ [✓] | Nama      | SATOR | Sell Out    | Fokus | Actions │
├──────────────────────────────────────────────────────────┤
│ [✓] | Ahmad     | Budi  | 10.000.000  | 30    | [Edit]  │
│ [✓] | Citra     | Budi  | 10.000.000  | 30    | [Edit]  │
│ [ ] | Dedi      | Budi  | 15.000.000  | 40    | [Edit]  │
│ [✓] | Fani      | Eka   | 10.000.000  | 30    | [Edit]  │
└──────────────────────────────────────────────────────────┘

[Set Target for Selected (3)]
```

**Klik "Edit":**
```
┌──────────────────────────────────────────────────────────┐
│ [✓] | Ahmad     | Budi  | [12.000.000] | [35] | [✓][✗] │
└──────────────────────────────────────────────────────────┘
```

---

## 🎨 UI COMPONENTS

### 1. Bulk Set Panel (Top)
- Input fields untuk target
- 2 buttons: "Apply to All" dan "Apply to Selected"
- Collapsible (bisa hide kalau tidak pakai)

### 2. Filter Bar
- Dropdown filter by SATOR/SPV
- Search box (cari nama)
- Role filter (sudah ada)

### 3. Table with Grouping
- Group by SATOR (collapsible)
- Checkbox per row
- Inline edit mode
- Pagination (20 per page)

### 4. Bulk Action Button
- Muncul kalau ada yang di-check
- Show count: "Set Target for Selected (5)"

---

## 💾 BACKEND CHANGES

### 1. Bulk Insert/Update Function
```sql
CREATE FUNCTION bulk_set_targets(
    p_user_ids UUID[],
    p_period_id UUID,
    p_target_sell_out NUMERIC,
    p_target_fokus INTEGER
) RETURNS INTEGER;
```

### 2. Get Users with Hierarchy
```sql
-- Return users grouped by SATOR
SELECT 
    u.id,
    u.full_name,
    u.role,
    sator.full_name as sator_name,
    ut.target_sell_out,
    ut.target_fokus
FROM users u
LEFT JOIN assignments_promotor_sator aps ON aps.promotor_id = u.id
LEFT JOIN users sator ON sator.id = aps.sator_id
LEFT JOIN user_targets ut ON ut.user_id = u.id
WHERE u.role = 'promotor'
ORDER BY sator.full_name, u.full_name;
```

---

## ✅ BENEFITS

### 1. Speed
- **Before:** 100 orang = 30 menit
- **After:** 100 orang = 1 menit (bulk set)

### 2. Organization
- Group by SATOR/SPV
- Easy to manage per team
- Clear hierarchy

### 3. Flexibility
- Bulk set untuk semua
- Bulk set untuk selected
- Individual edit

### 4. User Experience
- Inline edit (no expand/collapse)
- Checkbox select (familiar UX)
- Visual grouping

---

## 🔧 IMPLEMENTATION PRIORITY

### Phase 1: Table View + Inline Edit
- Replace ExpansionTile with Table
- Add inline edit mode
- Add checkbox selection

### Phase 2: Bulk Set
- Add bulk set panel
- Create bulk insert function
- Add "Apply to All" button

### Phase 3: Grouping
- Group by SATOR
- Collapsible groups
- Filter by SATOR

### Phase 4: Polish
- Pagination
- Search
- Loading states

---

## 📝 NEXT STEPS

1. **User approval** - Setuju dengan design ini?
2. **Implement Phase 1** - Table view
3. **Test with real data** - 100 promotor
4. **Iterate** - Improve based on feedback

---

**Question:** Apakah design ini sudah sesuai? Ada yang perlu diubah?
