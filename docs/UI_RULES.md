# UI Rules

Aturan ini wajib dipakai untuk semua pekerjaan UI di project ini.

## Tujuan

- Menjaga UI tetap konsisten antar role dan antar halaman.
- Mencegah perubahan acak yang memutus flow bisnis.
- Menghilangkan hardcoded visual dan hardcoded bisnis di widget.
- Menjadikan theme dan komponen sebagai sumber kebenaran tunggal.

## Hukum Utama

1. Jangan hardcode visual di page.
2. Jangan hardcode data bisnis di widget.
3. Semua page hanya menyusun section dan data.
4. Semua style harus datang dari token atau komponen standar.
5. Semua Home role harus mengikuti blueprint tertulis.
6. Jangan isi slot kosong dengan dummy yang menyesatkan.
7. Navigasi harus lewat route config atau named route.
8. Restore UI harus mengikuti referensi yang valid.

## Dilarang di Page

- `Color(...)`
- `TextStyle(...)` langsung di page
- `EdgeInsets` random di page
- `BorderRadius.circular(...)` random di page
- gradient manual di page
- shadow manual di page
- route string liar di widget
- nama area, nama role, nama orang, angka target, atau label bisnis yang seharusnya dinamis

## Wajib Dipakai

- `AppThemeTokens`
- `FieldThemeTokens`
- komponen reusable di `lib/ui/components/`
- pattern di `lib/ui/patterns/`
- named route atau navigation config
- enum / config map untuk status dan label

## Aturan Data

- Data harus diambil dari Supabase, profile, session, atau agregasi resmi.
- Jika data belum ada, tampilkan empty state yang jujur.
- Jangan pakai angka dummy, nama dummy, atau placeholder palsu untuk membuat UI terlihat penuh.
- Gunakan tabel agregasi jika halaman memang dashboard.

## Aturan Home / Dashboard

Setiap halaman home wajib punya blueprint:

- urutan section
- sumber data setiap section
- aksi utama
- period switch jika ada
- empty state jika data tidak ada

Perubahan struktur Home tidak boleh dilakukan tanpa:

- screenshot referensi
- blueprint tertulis
- persetujuan user

## Aturan Restore

Jika UI lama masih ada di HP user atau screenshot:

- screenshot menjadi referensi visual resmi
- restore harus mengikuti screenshot itu
- theme boleh distandardkan
- struktur informasi tidak boleh diubah sembarangan

## Checklist Review UI

Sebelum dianggap selesai, semua halaman harus lolos checklist ini:

1. Tidak ada hardcoded visual di page.
2. Tidak ada hardcoded bisnis di widget.
3. Semua warna dan typography datang dari token/theme.
4. Semua card, field, tab, dan badge memakai komponen/pattern standar.
5. Data datang dari source yang benar.
6. Empty/loading/error state jelas.
7. Navigasi nyambung.
8. Mobile layout aman.
9. Struktur halaman sesuai blueprint.
10. `flutter analyze` harus bersih.

## Prioritas Refactor

Urutan kerja UI standar:

1. theme tokens
2. komponen standar
3. shell dashboard
4. halaman referensi utama
5. role lain mengikuti referensi itu
6. bersihkan hardcoded sisa
