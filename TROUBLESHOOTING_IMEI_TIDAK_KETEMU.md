# Troubleshooting: Tab "Belum Lapor" ada counter tapi modal kosong

## Masalah
Tab "Belum Lapor" menampilkan counter 20, tapi saat klik "Lapor IMEI" modal kosong atau tidak menampilkan list IMEI.

## Penyebab
Ada 2 kemungkinan:

### 1. Filter Tanggal
**Counter di tab**: Menghitung SEMUA sales yang belum dilaporkan (tanpa filter tanggal)
**Modal**: Hanya menampilkan sales dalam date range (default: 7 hari terakhir)

Jadi jika ada 20 IMEI belum dilaporkan, tapi hanya 5 yang dalam 7 hari terakhir, maka modal hanya tampilkan 5.

### 2. Data Mismatch
- IMEI di `sales_sell_out` tidak match dengan IMEI di `imei_normalizations`
- Null IMEI di sales data
- Store assignment issue

## Solusi

### Solusi 1: Gunakan Tombol "Semua"
Saya sudah tambahkan tombol **"Semua"** di modal:
1. Klik FAB "Lapor IMEI"
2. Di modal, klik tombol **"Semua"** (warna hijau)
3. Modal akan load semua IMEI yang belum dilaporkan (hingga 1 tahun ke belakang)

### Solusi 2: Perluas Filter Tanggal
1. Klik tombol **"Filter"**
2. Pilih date range yang lebih lebar (misal: 30 hari, 90 hari)
3. Klik "Save"

### Solusi 3: Debug dengan Console
**Step 1: Buka Flutter Console**
- Di VS Code: View → Output → Flutter Run
- Atau terminal yang menjalankan `flutter run`

**Step 2: Cek Debug Print**
Saya sudah tambahkan debug print. Cari output:
```
=== DEBUG _loadUnreportedCount ===
User ID: [uuid]
Reported IMEI count: [number]
Total sales: [number]
Unreported sales count: [number]

=== DEBUG _loadUnreportedSales ===
User ID: [uuid]
Reported IMEI count: [number]
Date range: [start] to [end]
Total sales in date range: [number]
Unreported sales count: [number]
```

**Step 3: Analisa Output**
- `Reported IMEI count`: Berapa IMEI yang sudah dilaporkan
- `Total sales`: Total sales untuk user ini
- `Unreported sales count`: Counter di tab
- `Total sales in date range`: Sales dalam periode filter
- `Unreported sales count`: Jumlah di modal

**Contoh Output Masalah:**
```
=== DEBUG _loadUnreportedCount ===
Reported IMEI count: 10
Total sales: 100
Unreported sales count: 20  ← Counter di tab

=== DEBUG _loadUnreportedSales ===
Reported IMEI count: 10
Date range: 2026-02-28 to 2026-03-06
Total sales in date range: 15
Unreported sales count: 5  ← Hanya 5 dalam 7 hari terakhir
```

**Kesimpulan:** Ada 20 IMEI belum dilaporkan total, tapi hanya 5 yang dalam 7 hari terakhir.

## Query Database untuk Investigasi

### 1. Cek Total Sales vs Reported
```sql
-- Total sales untuk promotor
SELECT COUNT(*) as total_sales
FROM sales_sell_out 
WHERE promotor_id = '[PROMOTOR_USER_ID]';

-- Reported IMEIs
SELECT COUNT(*) as reported_imeis
FROM imei_normalizations 
WHERE promotor_id = '[PROMOTOR_USER_ID]';

-- Unreported sales (semua waktu)
SELECT COUNT(*) as unreported_all_time
FROM sales_sell_out s
WHERE s.promotor_id = '[PROMOTOR_USER_ID]'
AND NOT EXISTS (
  SELECT 1 FROM imei_normalizations i 
  WHERE i.imei = s.serial_imei
);

-- Unreported sales (7 hari terakhir)
SELECT COUNT(*) as unreported_last_7_days
FROM sales_sell_out s
WHERE s.promotor_id = '[PROMOTOR_USER_ID]'
AND s.transaction_date >= NOW() - INTERVAL '7 days'
AND NOT EXISTS (
  SELECT 1 FROM imei_normalizations i 
  WHERE i.imei = s.serial_imei
);
```

### 2. Cek Null IMEI
```sql
-- Sales dengan IMEI null
SELECT COUNT(*) as sales_with_null_imei
FROM sales_sell_out 
WHERE promotor_id = '[PROMOTOR_USER_ID]'
AND serial_imei IS NULL;

-- Sample data
SELECT id, transaction_date, serial_imei, store_id
FROM sales_sell_out 
WHERE promotor_id = '[PROMOTOR_USER_ID]'
AND serial_imei IS NULL
LIMIT 10;
```

### 3. Cek IMEI Duplikat
```sql
-- IMEI yang ada di sales tapi tidak di imei_normalizations
SELECT s.serial_imei, s.transaction_date
FROM sales_sell_out s
WHERE s.promotor_id = '[PROMOTOR_USER_ID]'
AND s.serial_imei IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM imei_normalizations i 
  WHERE i.imei = s.serial_imei
)
ORDER BY s.transaction_date DESC
LIMIT 20;
```

## Cara Fix

### Fix 1: Ubah Default Date Range
Jika ingin modal default tampilkan semua:
```dart
// Di initState modal
_startDate = DateTime.now().subtract(const Duration(days: 365));
_endDate = DateTime.now();
```

### Fix 2: Tambah Info di UI
Tambahkan info di modal:
```dart
Text(
  'Menampilkan ${_unreportedSales.length} dari $_unreportedCount unit',
  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
),
```

### Fix 3: Optimasi Query
Jika data besar (>1000), buat RPC function:
```sql
CREATE FUNCTION get_unreported_sales(p_promotor_id UUID, p_days_back INT DEFAULT 7)
RETURNS JSON
```

## Testing Sekarang

### Test 1: Tombol "Semua"
1. Klik FAB "Lapor IMEI"
2. Klik tombol **"Semua"** (hijau)
3. Modal harus tampilkan semua IMEI yang belum dilaporkan

### Test 2: Filter Manual
1. Klik tombol **"Filter"**
2. Pilih range: 30 hari terakhir
3. Klik "Save"
4. Modal harus tampilkan lebih banyak IMEI

### Test 3: Cek Console
1. Buka Flutter console
2. Cari debug print
3. Verifikasi angka match

## Jika Masih Kosong

### Step 1: Cek Data di Database
Jalankan query di atas untuk verifikasi data.

### Step 2: Cek Error di Console
- Ada error saat query?
- Network error?
- RLS policy blocking?

### Step 3: Test Query Manual
```dart
// Di Flutter console, test manual
final test = await Supabase.instance.client
    .from('sales_sell_out')
    .select('count')
    .eq('promotor_id', '[USER_ID]');
print('Test count: ${test.length}');
```

## Update yang Sudah Dilakukan

### ✅ Debug Print
- `_loadUnreportedCount()`: Print counter logic
- `_loadUnreportedSales()`: Print modal logic

### ✅ Tombol "Semua"
- Tombol hijau di modal
- Load semua data (1 tahun ke belakang)
- Icon: `Icons.all_inclusive`

### ✅ Extended Date Range
- Date picker: 365 hari ke belakang (dari 90)
- Default: 7 hari terakhir
- Tombol "Semua": 365 hari

## Next Action

1. **Test tombol "Semua"** - harus tampilkan semua IMEI
2. **Cek console** - lihat debug print
3. **Jika masih kosong** - jalankan query database

## Contact Support
Jika masih ada masalah:
1. Screenshot console output
2. Screenshot modal
3. User ID promotor
4. Output query database

---

**Status:** ✅ Solusi sudah diimplementasikan
**File:** `lib/features/promotor/presentation/pages/imei_normalization_page.dart`
**Update:** Tombol "Semua" + Debug print + Extended date range