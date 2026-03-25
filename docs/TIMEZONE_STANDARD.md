# TIMEZONE STANDARD - WITA (UTC+8)

## Aturan Wajib

### Database (Supabase)
```sql
-- Gunakan now_wita() untuk waktu sekarang
SELECT now_wita();

-- Gunakan today_wita() untuk tanggal hari ini
SELECT today_wita();

-- Convert timestamp ke WITA
SELECT to_wita(created_at);
```

### Flutter
```dart
import 'package:vtrack/core/utils/wita.dart';

// Waktu sekarang
final now = WitaTime.now();

// Format tanggal: "20 Jan 2026"
WitaTime.formatDate(dateTime);

// Format full: "20 Jan 2026, 14:30 WITA"
WitaTime.formatDateTime(dateTime);

// Parse dari database
final parsed = WitaTime.parse(supabaseTimestamp);
```

## Migration Required
Run: `20260120_wita_timezone.sql`

## Catatan
- WITA = Waktu Indonesia Tengah = Asia/Makassar
- Offset: UTC+8
- Gunakan KONSISTEN di semua tempat
