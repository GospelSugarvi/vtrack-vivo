# 🎯 REKOMENDASI ORDER - REQUIREMENT DETAIL

**Tanggal:** 2 Januari 2026  
**Status:** CRITICAL - Sistem sekarang KURANG DETAIL!

---

## ⚠️ MASALAH SISTEM SEKARANG

### **Logic Sekarang (KURANG DETAIL!):**

```python
# Dari code: get_stok_minimal_standard()

STOK_MINIMAL = {
    'A': {
        '1-2jt':   3 unit,  # ❌ Harga RANGE, tidak exact!
        '2-3jt':   3 unit,
        '3-4jt':   2 unit,
        '4-6jt':   2 unit,
        '>6jt':    1 unit,
    },
    # ... untuk grade B, C, D
}

# Problem:
Produk 1: Y19s 8/128 Black - Rp 2.499.000
Produk 2: Y19s 8/128 Gold - Rp 2.499.000
Produk 3: Y19s 6/128 Black - Rp 2.199.000

SEMUA masuk range '2-3jt'
→ Stok minimal sama: 3 unit
→ TIDAK DETAIL!
```

### **Contoh Problem:**

```
Skenario Real:

TOKO MTC (Grade A):
- Y19s 8/128 Black: 1 unit (stok toko)
- Y19s 8/128 Gold: 0 unit
- Y19s 6/128 Black: 2 unit

GUDANG PUSAT:
- Y19s 8/128 Black: 50 unit ✅
- Y19s 8/128 Gold: 0 unit ❌ (KOSONG!)
- Y19s 6/128 Black: 100 unit ✅

SISTEM SEKARANG (SALAH!):
Berdasarkan range harga '2-3jt', minimal 3 unit:
→ Rekomendasi:
  - Y19s 8/128 Black: 2 unit ✅ (OK, ada di gudang)
  - Y19s 8/128 Gold: 3 unit ❌ (SALAH! Gudang KOSONG!)
  - Y19s 6/128 Black: 1 unit ✅ (OK)

❌ Problem: Sistem recommend Y19s Gold 3 unit,
   tapi GUDANG TIDAK ADA STOCK!
```

---

## ✅ YANG USER MAU (DETAIL & EXACT!)

### **Logic Baru (DETAIL per Produk):**

```python
def calculate_rekomendasi_detail(toko, produk):
    """
    Input: 
    - toko: Toko object
    - produk: Produk object (EXACT: tipe, varian, warna, harga)
    
    Output:
    - qty_rekomendasi: Integer (exact qty untuk produk ini)
    """
    
    # 1. Get stok toko (EXACT match!)
    stok_toko = Stok.objects.filter(
        toko=toko,
        produk=produk,  # ← EXACT match! (tipe, varian, warna, harga)
        tipe_stok__in=['fresh', 'chip']
    ).count()
    
    # 2. Get stok gudang (EXACT match!)
    stok_gudang_record = StokGudangHarian.objects.filter(
        produk=produk,  # ← EXACT match!
        tanggal=today
    ).first()
    
    if not stok_gudang_record:
        return 0  # Tidak ada data stok gudang untuk produk ini
    
    stok_gudang = stok_gudang_record.stok_gudang
    
    if stok_gudang <= 0:
        return 0  # ❌ Gudang KOSONG, jangan recommend!
    
    # 3. Get stok minimal (per produk, bukan range!)
    stok_minimal = get_stok_minimal_per_produk(toko, produk)
    
    # 4. Calculate kebutuhan
    kebutuhan = stok_minimal - stok_toko
    
    if kebutuhan <= 0:
        return 0  # Stok toko cukup, tidak perlu order
    
    # 5. Qty rekomendasi = MIN(kebutuhan, stok_gudang)
    qty_rekomendasi = min(kebutuhan, stok_gudang)
    
    return qty_rekomendasi


def get_stok_minimal_per_produk(toko, produk):
    """
    Stok minimal DETAIL berdasarkan:
    1. Tipe produk (exact model)
    2. Varian (exact RAM/ROM)
    3. Warna (exact color)
    4. Harga (exact price)
    5. Grade toko
    """
    
    # Check if custom stok minimal exists for this exact produk
    try:
        custom = StokMinimalToko.objects.get(
            toko=toko,
            produk=produk  # ← EXACT match!
        )
        return custom.stok_minimal
    except StokMinimalToko.DoesNotExist:
        # Fallback: Use smart rules based on product attributes
        return calculate_smart_minimal(toko.grade, produk)


def calculate_smart_minimal(grade, produk):
    """
    Smart calculation berdasarkan:
    - Grade toko (A/B/C/D)
    - Product category (Y-series, V-series, X-series, iQOO)
    - Price tier (exact, bukan range!)
    - Sales velocity (optional: historical data)
    """
    
    # Category detection
    category = detect_category(produk.nama_model)
    # 'Y-series' (entry), 'V-series' (mid), 'X-series' (premium), 'iQOO' (gaming)
    
    # Price tier (more granular!)
    if produk.harga_srp <= 1500000:
        tier = 'ultra_low'
    elif produk.harga_srp <= 2000000:
        tier = 'low'
    elif produk.harga_srp <= 2500000:
        tier = 'low_mid'
    elif produk.harga_srp <= 3000000:
        tier = 'mid'
    elif produk.harga_srp <= 4000000:
        tier = 'mid_high'
    elif produk.harga_srp <= 6000000:
        tier = 'high'
    else:
        tier = 'ultra_high'
    
    # Matrix: Grade × Category × Tier
    SMART_MINIMAL = {
        'A': {  # Toko besar
            'Y-series': {
                'ultra_low': 5,
                'low': 4,
                'low_mid': 3,
            },
            'V-series': {
                'mid': 3,
                'mid_high': 2,
            },
            'X-series': {
                'high': 2,
                'ultra_high': 1,
            },
            'iQOO': {
                'mid_high': 2,
                'high': 1,
            }
        },
        'B': {  # Toko sedang
            'Y-series': {
                'ultra_low': 3,
                'low': 3,
                'low_mid': 2,
            },
            'V-series': {
                'mid': 2,
                'mid_high': 1,
            },
            'X-series': {
                'high': 1,
                'ultra_high': 1,
            },
            'iQOO': {
                'mid_high': 1,
                'high': 1,
            }
        },
        'C': {  # Toko kecil
            'Y-series': {
                'ultra_low': 2,
                'low': 2,
                'low_mid': 1,
            },
            'V-series': {
                'mid': 1,
                'mid_high': 1,
            },
            'X-series': {
                'high': 1,
                'ultra_high': 0,  # Tidak stock premium di toko kecil
            },
            'iQOO': {
                'mid_high': 1,
                'high': 0,
            }
        },
        'D': {  # Toko sangat kecil
            'Y-series': {
                'ultra_low': 1,
                'low': 1,
                'low_mid': 1,
            },
            'V-series': {
                'mid': 1,
                'mid_high': 0,
            },
            'X-series': {
                'high': 0,
                'ultra_high': 0,
            },
            'iQOO': {
                'mid_high': 0,
                'high': 0,
            }
        },
    }
    
    try:
        return SMART_MINIMAL[grade][category][tier]
    except KeyError:
        # Fallback default
        return 1
```

---

## 📊 CONTOH HASIL (BENAR!)

### **Input:**

```
TOKO: MTC (Grade A)

STOK TOKO:
- Y19s 8/128 Black: 1 unit
- Y19s 8/128 Gold: 0 unit
- Y19s 6/128 Black: 2 unit
- V40 12/256 Gold: 0 unit

STOK GUDANG (hari ini):
- Y19s 8/128 Black: 50 unit ✅
- Y19s 8/128 Gold: 0 unit ❌
- Y19s 6/128 Black: 100 unit ✅
- V40 12/256 Gold: 20 unit ✅
```

### **Process:**

```
Produk 1: Y19s 8/128 Black (Rp 2.499.000)
├─ Category: Y-series
├─ Tier: low_mid (2-2.5jt)
├─ Grade A → Minimal: 3 unit
├─ Stok toko: 1 unit
├─ Kebutuhan: 3 - 1 = 2 unit
├─ Stok gudang: 50 unit ✅
└─ Rekomendasi: MIN(2, 50) = 2 unit ✅

Produk 2: Y19s 8/128 Gold (Rp 2.499.000)
├─ Category: Y-series
├─ Tier: low_mid
├─ Grade A → Minimal: 3 unit
├─ Stok toko: 0 unit
├─ Kebutuhan: 3 - 0 = 3 unit
├─ Stok gudang: 0 unit ❌ KOSONG!
└─ Rekomendasi: 0 unit ❌ (Jangan recommend!)

Produk 3: Y19s 6/128 Black (Rp 2.199.000)
├─ Category: Y-series
├─ Tier: low (2-2.5jt)
├─ Grade A → Minimal: 4 unit
├─ Stok toko: 2 unit
├─ Kebutuhan: 4 - 2 = 2 unit
├─ Stok gudang: 100 unit ✅
└─ Rekomendasi: MIN(2, 100) = 2 unit ✅

Produk 4: V40 12/256 Gold (Rp 4.799.000)
├─ Category: V-series
├─ Tier: mid_high (4-6jt)
├─ Grade A → Minimal: 2 unit
├─ Stok toko: 0 unit
├─ Kebutuhan: 2 - 0 = 2 unit
├─ Stok gudang: 20 unit ✅
└─ Rekomendasi: MIN(2, 20) = 2 unit ✅
```

### **Output (Rekomendasi Final):**

```
📦 REKOMENDASI ORDER - MTC

✅ Y19s 8/128 Black: 2 unit (Rp 4.998.000)
   Stok Toko: 1 | Stok Gudang: 50 | Minimal: 3

❌ Y19s 8/128 Gold: - (SKIP - Gudang kosong!)
   Stok Toko: 0 | Stok Gudang: 0 | Status: ⚠️ Out of stock

✅ Y19s 6/128 Black: 2 unit (Rp 4.398.000)
   Stok Toko: 2 | Stok Gudang: 100 | Minimal: 4

✅ V40 12/256 Gold: 2 unit (Rp 9.598.000)
   Stok Toko: 0 | Stok Gudang: 20 | Minimal: 2

────────────────────────────────────
Total: 6 unit | Rp 18.994.000
[Edit] [Send WhatsApp] [Save]
```

---

## 🎯 RULES DETAIL

### **Rule 1: EXACT MATCH (Wajib!)**

```
Produk di rekomendasi HARUS EXACT match:
✅ Nama model: Y19s (bukan Y19, bukan Y19s Pro)
✅ Varian: 8/128 (bukan 6/128, bukan 8/256)
✅ Warna: Black (bukan Gold, bukan Blue)
✅ Harga: Rp 2.499.000 (exact dari database)

TIDAK BOLEH generic/range!
```

### **Rule 2: Stok Gudang = ACUAN**

```
IF stok_gudang <= 0:
    ❌ Jangan recommend!
    ❌ Jangan tampilkan di list
    ❌ Or tampilkan dengan status "Out of stock"

ELSE:
    ✅ Calculate recommendation
    ✅ Show availability
```

### **Rule 3: Stok Minimal per Kategori**

```
BUKAN berdasarkan range harga!
TAPI berdasarkan:
1. Product category (Y/V/X/iQOO)
2. Price tier (lebih granular: 7 tiers, bukan 5)
3. Grade toko (A/B/C/D)

Example:
Y19s 8/128 (Y-series, low_mid, Grade A) → Minimal: 3
V40 12/256 (V-series, mid_high, Grade A) → Minimal: 2
X200 Pro (X-series, ultra_high, Grade A) → Minimal: 1
iQOO Z9 (iQOO, mid_high, Grade A) → Minimal: 2
```

### **Rule 4: Custom Override**

```
SATOR bisa set custom minimal per toko per produk:
- MTC: Y19s 8/128 Black minimal 5 unit (override default 3)
- Karena toko ini laris untuk produk ini

Table: StokMinimalToko
- toko_id
- produk_id (exact!)
- stok_minimal (custom value)
```

---

## 📱 UI/UX CHANGES

### **Rekomendasi Table (Detail!):**

```
┌─────────────────────────────────────────────────────────┐
│ 📦 REKOMENDASI ORDER - Transmart MTC (Grade A)          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Produk                    │Toko│Gdg │Min│Rekom│ Total  │
├───────────────────────────┼────┼────┼───┼─────┼────────┤
│ Y19s 8/128 Black          │ 1  │ 50 │ 3 │  2  │ 5.0jt  │
│ Y19s 6/128 Black          │ 2  │100 │ 4 │  2  │ 4.4jt  │
│ V40 12/256 Gold           │ 0  │ 20 │ 2 │  2  │ 9.6jt  │
├───────────────────────────┼────┼────┼───┼─────┼────────┤
│ Y19s 8/128 Gold ⚠️        │ 0  │ 0  │ 3 │  -  │   -    │
│ (Stok gudang kosong!)     │    │    │   │     │        │
└─────────────────────────────────────────────────────────┘

Legend:
Toko = Stok di toko sekarang
Gdg = Stok di gudang pusat
Min = Stok minimal yang harus ada
Rekom = Qty yang direkomendasikan

Total: 6 unit | Rp 18.994.000

[✏️ Edit Manual] [💬 Send WhatsApp] [💾 Save]
```

### **Out of Stock Warning:**

```
⚠️ PRODUK TIDAK TERSEDIA (3 produk):

Y19s 8/128 Gold
└─ Stok gudang: 0
└─ Kebutuhan: 3 unit
└─ Action: Tidak bisa order

V30 8/256 Blue
└─ Stok gudang: 0
└─ Kebutuhan: 2 unit

[View All Out of Stock] [Hide]
```

---

## 🎯 KESIMPULAN

### **Yang HARUS diubah:**

```
❌ OLD: Berdasarkan range harga
   Grade A, harga 2-3jt → minimal 3 unit
   (Semua produk 2-3jt sama!)

✅ NEW: Berdasarkan produk exact
   Y19s 8/128 Black (Y-series, low_mid, Grade A) → minimal 3 unit
   Y19s 8/128 Gold (Y-series, low_mid, Grade A) → minimal 3 unit
   
   TAPI kalau gudang kosong Gold:
   - Black: recommend 2 unit ✅
   - Gold: skip (gudang kosong!) ❌
```

### **Benefit:**

```
✅ Akurat (tidak recommend yang tidak ada)
✅ Detail (exact tipe, varian, warna, harga)
✅ Smart (per kategori produk)
✅ Flexible (custom per toko-produk)
✅ Real-time (based on actual warehouse stock)
```

---

**VERIFIED!** Sistem baru harus DETAIL & EXACT! 🎯✅
