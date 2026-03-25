# UI Standard System

Dokumen ini adalah acuan visual resmi untuk seluruh aplikasi.  
Tujuan: semua role, semua halaman, dan semua kartu memakai pola yang sama.

## Prinsip

- Satu app, satu bahasa visual.
- Role boleh beda isi, tapi tidak boleh beda fondasi.
- Jangan bikin komponen baru kalau token lama sudah cukup.
- Jangan set ukuran manual acak di halaman.

## Typography

Gunakan tipe huruf dari theme yang sudah ada di `lib/core/theme/app_theme.dart`.

Skala resmi:

- `Page Title`: 24, weight 800
- `Section Title`: 18, weight 700
- `Card Title`: 16, weight 700
- `Body`: 14, weight 400-500
- `Meta`: 12, weight 500
- `Caption`: 11, weight 500
- `Nav Label`: 11, weight 600

Larangan:

- jangan ada `fontSize: 8`
- jangan ada label nav berbeda per role
- jangan ada `fontWeight` acak untuk teks yang sama

## Spacing

Pakai kelipatan tetap:

- `4`
- `8`
- `12`
- `16`
- `20`
- `24`
- `32`

Aturan pakai:

- gap antar item kecil: `8`
- gap antar blok dalam card: `12`
- padding card: `16`
- gap antar section: `24`
- padding halaman mobile: `16`
- padding halaman desktop: `24`

Larangan:

- jangan pakai `7`, `13`, `18`, `22` tanpa alasan sistem

## Radius

Gunakan token tetap:

- `sm = 8`
- `md = 12`
- `lg = 16`
- `pill = 999`

Aturan:

- input/button kecil: `md`
- card: `lg`
- chip/badge/segmented: `pill`

Larangan:

- jangan campur `10`, `11`, `14`, `18`, `20` di komponen setara

## Line dan border

Aturan resmi:

- border normal: `1`
- border focus: `2`
- divider pakai warna border theme
- jangan pakai border random per halaman

## Warna

Semua warna harus ambil dari `AppColors`.

Makna warna:

- `primary`: aksi utama
- `success`: berhasil, tercapai
- `warning`: perlu perhatian
- `danger`: gagal, kurang, error
- `info`: informasi tambahan
- `surface`: card dan panel
- `background`: latar halaman

Larangan:

- jangan pakai warna baru langsung di halaman
- jangan pakai `Colors.*` untuk state utama kalau sudah ada token

## Header halaman

Struktur header dashboard semua role:

1. sapaan `Selamat datang,`
2. nama user
3. chip utama
4. info kecil sekunder
5. tanggal
6. segmented control periode

Aturan chip utama:

- Promotor: toko
- SATOR: jabatan
- SPV: jabatan
- Trainer: jabatan

Info kecil sekunder:

- area

## Bottom navigation

Semua role harus sama:

- `Home`
- `Workplace`
- `Ranking`
- `Chat`
- `Profil`

Aturan:

- icon set harus konsisten
- label harus sama persis
- ukuran label `11`
- item count tetap `5`

## Tab periode

Selalu pakai segmented control yang sama.

Label resmi:

- `Harian`
- `Mingguan`
- `Bulanan`

Aturan:

- bentuk pill
- tinggi sama di semua halaman
- tidak boleh memotong teks

## Card standard

Semua card informasi utama harus punya pola:

1. judul
2. subjudul singkat jika perlu
3. metrik utama
4. grid ringkasan 4 item
5. progress bar jika relevan
6. aksi atau tap target jika relevan

Urutan isi card target:

1. `Target`
2. `Realisasi`
3. `Sisa`
4. `Pencapaian`

Kalau ada domain turunan:

1. `All Type`
2. `Produk Fokus`
3. `Tipe Khusus`

## Tabel dan list

List item standar:

- avatar atau icon
- title
- subtitle
- badge status
- action di kanan

Tabel atau row summary:

- header harus singkat
- angka rata kanan
- status pakai badge, bukan warna teks liar

## Empty, loading, error

Semua halaman wajib punya pola tetap:

- loading: indicator + teks singkat
- empty: title + penjelasan + aksi
- error: title + pesan singkat + tombol ulangi

Jangan:

- halaman kosong putih
- loading muter tanpa teks
- snackbar sebagai satu-satunya error state

## Pola role

Role boleh beda isi, tapi urutan tetap:

### Home

- header
- target harian
- snapshot performa
- aktivitas utama
- insight tambahan

### Workplace

- menu kerja utama
- tools sekunder

### Ranking

- leaderboard
- posisi user

### Chat

- daftar ruang chat

### Profil

- identitas
- pengaturan dasar

## Checklist sebelum merge

- apakah halaman memakai token spacing resmi
- apakah radius mengikuti sistem
- apakah label role dan nav seragam
- apakah urutan isi card target sudah sama
- apakah warna state memakai token global
- apakah tidak ada istilah atau bentuk baru yang lahir sendiri
