# Schedule System Updates - 4 Februari 2026

## REVISI 1: Notifikasi Status Jadwal ke Promotor ✅

### Problem
Promotor tidak tahu apakah jadwal mereka sudah di-approve atau di-reject oleh SATOR, dan tidak bisa melihat alasan rejection.

### Solution
**1. Status Badge Display**
- Menambahkan status badge di halaman jadwal promotor
- Status yang ditampilkan:
  - **Draft** (abu-abu) - Jadwal masih draft, belum di-submit
  - **Menunggu Review** (orange) - Jadwal sudah di-submit, menunggu SATOR review
  - **Disetujui** (hijau) - Jadwal sudah di-approve SATOR
  - **Ditolak** (merah) - Jadwal di-reject SATOR

**2. Rejection Reason Display**
- Jika status = rejected, tampilkan card merah dengan alasan penolakan
- Alasan penolakan diambil dari field `rejection_reason` di tabel `schedules`
- Promotor bisa langsung tahu kenapa jadwalnya ditolak

**3. Visual Feedback**
- Icon yang sesuai untuk setiap status
- Color coding yang jelas
- Informasi yang mudah dipahami

### Files Modified
- `lib/features/promotor/presentation/pages/jadwal_bulanan_page_new.dart`
  - Added `_scheduleStatus` and `_rejectionReason` state variables
  - Updated `_checkSchedule()` to fetch status and rejection reason
  - Added `_buildStatusBadge()` function
  - Added rejection reason display in UI

### Flow
1. Promotor buka halaman Jadwal Bulanan
2. Pilih bulan
3. Jika ada jadwal, tampilkan:
   - Status badge (Draft/Menunggu Review/Disetujui/Ditolak)
   - Jika ditolak, tampilkan alasan penolakan dalam card merah
4. Promotor bisa klik "Lihat Jadwal" untuk melihat detail atau edit

---

## REVISI 2: Tambah Shift Type "Fullday" ✅

### Problem
Hanya ada shift Pagi dan Siang. Perlu ada opsi Fullday untuk promotor yang kerja seharian.

### Solution
**1. Database Changes**
- Update constraint di tabel `shift_settings` untuk include 'fullday'
- Insert default fullday settings: 08:00-22:00
- Update function `get_shift_display()` untuk handle fullday

**2. Admin Page**
- Tambah card "Shift Fullday" di halaman Pengaturan Jam Kerja
- Admin bisa set jam mulai dan selesai untuk fullday per area
- Default: 08:00-22:00

**3. Promotor Page**
- Tambah opsi "Shift Fullday" di shift picker
- Icon: wb_sunny_outlined
- Color: Purple
- Tampil di legend kalender

**4. SATOR Page**
- Update schedule detail page untuk recognize fullday
- Color: Purple
- Icon: wb_sunny_outlined

### Files Modified
- `supabase/add_fullday_shift_type.sql` (NEW)
  - Alter table constraint
  - Insert default fullday settings
  - Update get_shift_display function

- `lib/features/promotor/presentation/pages/jadwal_bulanan_page_new.dart`
  - Added `fullday` to ShiftType enum
  - Added fullday to _shiftSettings map
  - Updated _getShiftColor() to return purple for fullday
  - Added fullday to legend
  - Added fullday option in ShiftPickerSheet

- `lib/features/admin/presentation/pages/shift_settings_page.dart`
  - Added fullday to _shiftTimes map (08:00-22:00)
  - Added fullday card in ListView

- `lib/features/sator/presentation/pages/jadwal/schedule_detail_page.dart`
  - Updated _getShiftColor() to return purple for fullday
  - Updated _getShiftIcon() to return wb_sunny_outlined for fullday

### Shift Types Summary
| Shift Type | Default Time | Color  | Icon              |
|------------|--------------|--------|-------------------|
| Pagi       | 08:00-16:00  | Orange | wb_sunny          |
| Siang      | 13:00-21:00  | Blue   | wb_twilight       |
| Fullday    | 08:00-22:00  | Purple | wb_sunny_outlined |
| Libur      | -            | Grey   | event_busy        |

### Database Migration
Run this SQL to add fullday support:
```sql
-- Run: supabase/add_fullday_shift_type.sql
```

---

## Testing Checklist

### Revisi 1: Notifikasi Status
- [ ] Promotor buat jadwal baru → Status: Draft
- [ ] Promotor submit jadwal → Status: Menunggu Review
- [ ] SATOR approve jadwal → Promotor lihat Status: Disetujui
- [ ] SATOR reject jadwal dengan alasan → Promotor lihat Status: Ditolak + alasan tampil

### Revisi 2: Fullday Shift
- [ ] Admin buka Pengaturan Jam Kerja → Ada card Shift Fullday
- [ ] Admin set jam fullday (misal 07:00-21:00) → Simpan berhasil
- [ ] Promotor buat jadwal → Tap tanggal → Ada opsi "Shift Fullday"
- [ ] Promotor pilih fullday → Kalender tampil warna purple
- [ ] SATOR review jadwal → Fullday tampil dengan warna purple

---

## Database Schema Reference

### schedules table
```sql
- promotor_id: UUID
- schedule_date: DATE
- shift_type: TEXT (pagi/siang/fullday/libur)
- status: TEXT (draft/submitted/approved/rejected)
- rejection_reason: TEXT (nullable)
- month_year: TEXT (YYYY-MM)
```

### shift_settings table
```sql
- shift_type: TEXT (pagi/siang/fullday)
- start_time: TIME
- end_time: TIME
- area: TEXT
- active: BOOLEAN
```

---

## Notes
- Fullday shift cocok untuk promotor yang kerja dari pagi sampai malam
- Admin bisa set jam fullday berbeda per area
- Rejection reason wajib diisi SATOR saat reject jadwal
- Status badge auto-update setiap kali promotor buka halaman jadwal
