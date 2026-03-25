# Stok Gudang System Update - 04 February 2026

## Overview
Updated the warehouse stock (Stok Gudang) system to improve the workflow with date selection as the entry point.

## Changes Made

### 1. **StokGudangPage** - Main Dashboard
**File**: `lib/features/sator/presentation/pages/sell_in/stok_gudang_page.dart`

**Changes**:
- Removed "Update Stok" button from AppBar
- Added floating action button "Buat Stok Baru" (Create New Stock)
- Added date picker dialog for selecting stock date
- Added function `_showCreateStockDialog()` to show date selection
- Added function `_checkAndNavigateToScan()` to check existing stock and navigate

**Flow**:
1. User clicks "Buat Stok Baru" button
2. Date picker dialog appears
3. User selects date (can be today, yesterday, or future dates within 7 days)
4. System checks if stock already exists for that date
5. Navigate to scan page with date and status information

### 2. **ScanStokGudangPage** - Upload & Parse Page
**File**: `lib/features/sator/presentation/pages/sell_in/scan_stok_gudang_page.dart`

**Changes**:
- Added `params` parameter to constructor to receive navigation data
- Removed `_checkStockStatus()` function (now receives data from params)
- Updated `initState()` to extract date and status from params
- Updated AppBar to show selected date
- Updated `_saveStok()` to use `_selectedDate` instead of `DateTime.now()`
- Added emoji debug prints (🔍 ✅ ❌)

**Received Parameters**:
```dart
{
  'selectedDate': DateTime,
  'hasExistingData': bool,
  'createdBy': String?,
  'createdAt': String?,
}
```

### 3. **Router Configuration**
**File**: `lib/core/router/app_router.dart`

**Changes**:
- Updated `sator-scan-gudang` route to accept `extra` parameters
- Changed from `const ScanStokGudangPage()` to `ScanStokGudangPage(params: params)`

### 4. **Database Function**
**File**: `supabase/add_stok_gudang_date_check.sql`

**New Function**: `get_stok_gudang_status_for_date(p_tanggal DATE)`

**Purpose**: Check if stock data exists for a specific date

**Returns**:
```json
{
  "has_data": boolean,
  "created_by": "Full Name",
  "created_at": "2026-02-04T10:30:00+08",
  "total_items": 12
}
```

**Usage**:
```sql
SELECT * FROM get_stok_gudang_status_for_date('2026-02-04');
```

## User Flow

### Before (Old Flow)
1. Open Stok Gudang page
2. Click "Update Stok" button
3. Upload photo (always for today)
4. AI parses data
5. Save to database

### After (New Flow)
1. Open Stok Gudang page
2. Click "Buat Stok Baru" floating button
3. **Select date** in date picker dialog
4. System checks if stock exists for that date
5. Navigate to scan page with date info
6. If stock exists, show warning banner with creator info
7. Upload photo
8. AI parses data
9. Save to database **for selected date**

## Benefits

1. **Date Flexibility**: Can create stock for past or future dates
2. **Better Information**: Shows who created stock and when
3. **Clearer Entry Point**: "Buat Stok Baru" is more intuitive than "Update Stok"
4. **Prevents Confusion**: User knows exactly which date they're working on
5. **Better UX**: Date shown in AppBar throughout the process

## Technical Notes

### Date Range
- Minimum: 7 days ago
- Maximum: 7 days from now
- Can be adjusted in `firstDate` and `lastDate` parameters

### Stock Status Check
- Checks database before navigation
- Shows warning if data already exists
- Displays creator name and time
- Update will overwrite existing data (upsert behavior)

### AI Parsing
- Still uses Gemini 2.5 Flash
- Same parsing logic (model, variant, color, stok, otw)
- Same filtering (skip DM/Demo products)

### Database
- Uses existing `stok_gudang_harian` table
- UNIQUE constraint: (product_id, variant_id, tanggal)
- Upsert behavior: INSERT or UPDATE if exists

## Testing Checklist

- [ ] Date picker shows correct date range
- [ ] Date picker displays in Indonesian format
- [ ] System checks stock status for selected date
- [ ] Warning banner shows when stock exists
- [ ] Selected date displays in AppBar
- [ ] Photo upload and AI parsing works
- [ ] Save function uses selected date (not today)
- [ ] Can create stock for yesterday
- [ ] Can create stock for tomorrow
- [ ] Can update existing stock (overwrite)

## SQL Migration

Run this SQL file to add the new function:
```bash
supabase/add_stok_gudang_date_check.sql
```

## Related Files

### Modified
- `lib/features/sator/presentation/pages/sell_in/stok_gudang_page.dart`
- `lib/features/sator/presentation/pages/sell_in/scan_stok_gudang_page.dart`
- `lib/core/router/app_router.dart`

### Created
- `supabase/add_stok_gudang_date_check.sql`
- `docs/STOK_GUDANG_SYSTEM_UPDATE_04FEB2026.md`

### Unchanged (Still Used)
- `lib/features/sator/services/stok_gudang_ai_service.dart`
- `supabase/add_stok_gudang_functions.sql`
- `supabase/update_gudang_stock_v2.sql`

## Future Improvements

1. **History View**: Show list of all created stock dates
2. **Edit Mode**: Allow editing existing stock without re-uploading photo
3. **Comparison**: Compare stock between dates
4. **Notifications**: Notify team when stock is created/updated
5. **Validation**: Prevent creating stock for dates too far in past/future
6. **Audit Log**: Track all changes to stock data
