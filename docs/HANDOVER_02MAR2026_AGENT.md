# HANDOVER AGENT - 02 Mar 2026

## Ringkasan Singkat
Tujuan sesi ini: audit cepat project Flutter, perbaiki error/warning yang paling berisiko, dan kurangi noise analyzer tanpa mengubah behavior utama.

Hasil:
- `flutter analyze` global turun dari **588** issue menjadi **551** issue.
- Warning tersisa saat ini: **31 warning** (dominan di modul Promotor, mostly `unused/dead code`).
- File kritis yang sudah diperbaiki lulus bersih:
  - `lib/main.dart`
  - `lib/core/router/app_router.dart`
  - `lib/features/chat/repository/chat_repository.dart`
  - `lib/features/chat/cubit/chat_room_cubit.dart`
  - `lib/core/utils/error_handler.dart`

Validasi terakhir untuk file kritis:
```bash
/home/geger/flutter/bin/flutter analyze lib/main.dart lib/core/router/app_router.dart lib/features/chat/repository/chat_repository.dart lib/features/chat/cubit/chat_room_cubit.dart lib/core/utils/error_handler.dart
# No issues found!
```

## Masalah Utama yang Sudah Diperbaiki
1. **Logging production (`print`)** di area bootstrap/chat diganti ke `debugPrint`.
2. **Router cast risk**: `state.extra as Map<String, dynamic>?` diubah jadi type-safe check agar tidak mudah crash.
3. **Async error handler bug** di `chat_room_cubit`:
   - `.catchError((e){...})` pada future yang mengembalikan `int` diganti `.onError((error, stackTrace) => 0)`.
4. **Unreachable switch case** di error handler dibersihkan.
5. **Cleanup warning aman**: beberapa `unused import`, `unused optional key`, dan dead helper function yang tidak dipakai.

## File yang Diedit di Sesi Ini
- `lib/main.dart`
- `lib/core/router/app_router.dart`
- `lib/features/chat/repository/chat_repository.dart`
- `lib/features/chat/cubit/chat_room_cubit.dart`
- `lib/core/utils/error_handler.dart`
- `lib/features/admin/presentation/admin_dashboard.dart`
- `lib/features/admin/presentation/pages/stock_rules_page.dart`
- `lib/features/admin/presentation/pages/admin_bonus_page.dart`
- `lib/features/admin/presentation/pages/admin_products_page.dart`
- `lib/features/promotor/presentation/pages/stok_toko_page.dart`
- `lib/features/sator/presentation/pages/kpi_bonus_page.dart`
- `lib/features/sator/presentation/pages/sell_in/list_toko_page.dart`
- `lib/features/sator/presentation/pages/sell_in/scan_stok_gudang_page.dart`
- `lib/features/sator/presentation/pages/sell_in/stok_gudang_page.dart`
- `lib/features/sator/presentation/pages/visiting/visiting_dashboard_page.dart`
- `list_models.dart`

## Warning Tersisa (31) - Fokus Besok
Prioritas praktis: selesaikan warning dulu (karena jumlah kecil dan mostly safe), baru lanjut info-level lint.

### Cluster terbesar
- `lib/features/promotor/presentation/pages/aktivitas_harian_page.dart`
  - unused field, dead_code, dead_null_aware_expression, unused optional param.
- `lib/features/promotor/presentation/tabs/promotor_home_tab.dart`
  - unused local vars/unused private methods.
- `lib/features/promotor/presentation/pages/bonus_detail_page.dart`
  - beberapa method private tidak terpakai.
- `lib/features/promotor/presentation/pages/cari_stok_page.dart`
  - unused field/method.

### Lainnya
- `clock_in_page.dart`, `sell_out_page.dart`, `stock_validation_page.dart`, `promotor_dashboard.dart`, `promotor_profil_tab.dart`.

## Command Cepat untuk Lanjut Besok
Gunakan path Flutter lokal karena `flutter` tidak ada di PATH sandbox:

```bash
/home/geger/flutter/bin/flutter analyze
/home/geger/flutter/bin/flutter analyze | rg "warning •"
```

Untuk fokus warning saja:
```bash
/home/geger/flutter/bin/flutter analyze | rg "warning •|^$"
```

## Strategi Lanjutan yang Disarankan
1. Bereskan 31 warning dulu sampai 0 (safe cleanup).
2. Setelah warning 0, baru tackle info lint bertahap:
   - `avoid_print`
   - `withOpacity` -> `withValues(alpha: ...)`
   - `use_build_context_synchronously`
   - deprecations (`DropdownButtonFormField.value`, dll)
3. Jalankan smoke test minimal:
   - `flutter run -d <device_id_android>`
   - Cek login, dashboard promotor, chat room open/send message.

## Catatan Lingkungan
- Repo ini **bukan git repo** (tidak ada `.git` di root workspace ini), jadi tidak ada `git diff/status` untuk tracking perubahan.
- Untuk menjalankan `flutter analyze` dari agent sandbox, butuh binary:
  - `/home/geger/flutter/bin/flutter`

