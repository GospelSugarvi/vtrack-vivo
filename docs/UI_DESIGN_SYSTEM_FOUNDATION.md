# UI System Rules - Mobile App

Tujuan:

- membuat UI konsisten
- membuat UI sederhana
- membuat UI mudah dirawat
- melarang styling liar per halaman

## 1. Design Tokens

Semua warna, spacing, radius, dan typography wajib memakai token global.

Color tokens resmi:

- `primary = #0F7B6C`
- `background = #F5F6F8`
- `surface = #FFFFFF`
- `surfaceVariant = #EEF1F4`
- `textPrimary = #1F2933`
- `textSecondary = #6B7280`
- `border = #E5E7EB`
- `success = #2E7D32`
- `warning = #F59E0B`
- `danger = #DC2626`

Aturan:

- tidak boleh hardcode warna di page
- status color hanya dipakai untuk status, bukan dekorasi bebas
- satu screen maksimal memakai 3 warna dominan

## 2. Spacing System

Scale resmi:

- `xs = 4`
- `sm = 8`
- `md = 16`
- `lg = 24`
- `xl = 32`

Aturan:

- padding card = `md`
- jarak antar card = `md`
- jarak antar section = `lg`
- tidak boleh membuat padding random

## 3. Radius System

Scale resmi:

- `sm = 8`
- `md = 12`
- `lg = 16`

Aturan:

- card radius = `lg`
- button radius = `md`
- chip radius = `lg`

## 4. Typography

Style resmi:

- `pageTitle = 20 / bold`
- `sectionTitle = 16 / semibold`
- `body = 14 / regular`
- `caption = 12 / regular`

Aturan:

- semua text di screen mengikuti style ini
- informasi sekunder pakai `caption`
- jangan membuat hierarki font baru di page

## 5. Icon Rule

Aturan ikon:

- icon library: `Material Icons`
- `small = 16`
- `normal = 24`
- `large = 32`

Icon container:

- size = `48`
- background = `surfaceVariant`

Aturan:

- tidak boleh icon warna random
- icon mengikuti warna token atau status

## 6. Card Design

Semua card wajib memakai `AppCard`.

Style resmi:

- background = `surface`
- radius = `16`
- shadow = ringan
- padding = `16`

Dilarang:

- gradient card
- warna card random
- border tebal
- kartu dekoratif yang mendobel isi kartu lain

## 7. Reusable Components

Komponen wajib:

- `AppHeader`
- `AppCard`
- `AppButton`
- `AppListItem`
- `AppMenuCard`
- `AppBadge`
- `AppSectionHeader`
- `AppInput`
- `AppEmptyState`

Aturan:

- page tidak boleh membuat card sendiri
- page tidak boleh membuat layout visual sendiri jika sudah ada komponen resmi

## 8. Layout Templates

Semua halaman hanya boleh mengikuti salah satu template ini:

### Dashboard

- Header
- Summary stats
- Quick actions
- Recent activity

### Menu Grid

- Header
- Section title
- Grid menu

Aturan grid:

- mobile default = 2 kolom
- width lega/tablet = 3 kolom

### List Page

- Header
- Search
- Filter
- List item

### Detail Page

- Header
- Main info card
- Tabs
- Detail content

### Feed Page

- User
- Photo
- Product info
- Actions

### Chat Page

- Section header
- Room list
- Floating button

Aturan:

- halaman baru harus memilih salah satu template ini
- kalau butuh variasi, variasinya dibuat di layer pattern, bukan di page langsung

## 9. Navigation

Bottom navigation harus konsisten:

- Home
- Laporan
- Ranking
- Chat
- Profil

Aturan:

- role hanya mengubah isi halaman
- role tidak mengubah struktur bottom navigation

## 10. Code Rules

Dilarang:

- hardcoded color
- hardcoded spacing
- card style custom per page
- icon style random

Wajib:

- gunakan design tokens
- gunakan reusable components
- ikuti layout template

## 11. Refactor Order

Urutan implementasi:

1. design tokens
2. reusable components
3. menu grid screen
4. dashboard screen
5. list screens
6. feed screens
7. chat screens

## 12. Practical Screen Rules

Aturan tambahan untuk semua refactor screen:

- jangan mendobel informasi antar card
- quick actions harus padat, seragam, dan tidak menyisakan ruang kosong besar
- potong teks yang tidak dibutuhkan
- gunakan maksimal 1 hero utama per screen
- status/warning/info cukup satu kali, jangan diulang di beberapa blok

## Target

Hasil yang diharapkan:

- UI konsisten
- UI mudah dirawat
- tidak ada lagi desain random per halaman
