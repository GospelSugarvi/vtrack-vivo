# Next Handover 2026-04-07

Dokumen ini untuk melanjutkan item non-VAST besok. Fokus hari ini dipusatkan ke `Vast Finance`.

## Sudah Selesai Hari Ini

- `Vast promotor`
  - form input sekarang tidak default ke `pending`, `pekerjaan pertama`, dan `tenor 12`
  - `Tanggal Pengajuan` jadi field pertama
  - placeholder jadi `Tap untuk memilih`
  - tombol submit jadi `Kirim` / `Sedang mengirim`
  - submit sukses langsung pindah ke tab `History`
  - label `ACC` di UI diganti jadi `Closing`
- `Vast sator/spv`
  - label export `ACC` diganti `Closing`
  - tabel performa sudah disiapkan untuk kolom `Nominal Closing`
  - ringkasan hero memakai istilah `Nominal Closing`
- `Data VAST`
  - migration baru: [20260407_vast_closing_nominal_snapshots.sql](/home/geger/Documents/project%20APK/project%20vivo%20apk/supabase/migrations/20260407_vast_closing_nominal_snapshots.sql)
  - helper nominal closing dihitung dari `product_variants.srp`
  - snapshot `promotor`, `sator`, `spv` dioverride untuk membawa `closing_omzet`

## Catatan Penting VAST

- Istilah bisnis yang dipakai user: `ACC` dianggap sama dengan `Closing`, jadi tampilan harus pakai `Closing`.
- `Nominal Closing` harus pakai `SRP barang`.
- `Reject` tetap masuk hitungan `input`, tetapi nominal closing = `0`.

## Item Belum Dikerjakan

### 1. Chat Gambar

Masalah user:
- kirim gambar di semua chat biasa tidak jalan
- saat pilih dari galeri, tidak terjadi apa-apa
- tidak ada error
- dulu sempat berfungsi

File yang perlu dicek:
- [chat_room_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/chat/presentation/pages/chat_room_page.dart)
- [chat_room_cubit.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/chat/cubit/chat_room_cubit.dart)
- [chat_repository.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/chat/repository/chat_repository.dart)
- [message_input.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/chat/presentation/widgets/message_input.dart)

Temuan awal:
- alur picker ada di `chat_room_page.dart` dan `message_input.dart`
- route upload/send image ada di repository
- file-file chat sedang dirty dari agent lain, jadi merge harus hati-hati

### 2. Input Stok Promotor

Permintaan user:
- daftar `tipe produk` harus muncul instan saat halaman dibuka
- popup pilihan produk harus padat, satu layar, header jangan makan tempat
- setelah input IMEI, tombol jadi `Kirim` / `Sedang mengirim`

File utama:
- [stock_input_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stock_input_page.dart)

Temuan awal:
- file ini juga sedang dirty
- ada `showModalBottomSheet` untuk pilih varian
- ada teks submit `SIMPAN X IMEI` yang perlu disesuaikan dengan permintaan user

### 3. Form Isi Penjualan Promotor

Permintaan user:
- field tetap sama
- header dibuat compact
- area tipe dan IMEI dipadatkan
- targetnya form tidak perlu banyak scroll

File utama:
- [sell_out_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/sell_out_page.dart)

Temuan awal:
- file sudah punya tombol `Kirim` / `Sedang mengirim...`
- perlu fokus ke layout, bukan perubahan field bisnis

### 4. IMEI Normalisasi Sator

Permintaan user:
- saat klik `Siap Scan` harus muncul dialog konfirmasi
- dialog ada upload `foto bukti` opsional
- setelah terkirim, kirim card ke grup toko promotor
- di chat, IMEI pada card bisa di-copy dengan long press
- notif promotor tetap arah ke halaman `IMEI Normalisasi`

File utama:
- [imei_normalisasi_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/pages/imei_normalisasi_page.dart)
- [imei_normalization_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/imei_normalization_page.dart)
- kemungkinan juga chat repository / chat room page

### 5. Sellout Insight Week-to-Week

Permintaan user:
- compare week manual
- promotor: `sellout all type`, `produk fokus`, `vast input`, `vast closing`
- sator: compare per toko untuk `sellin`, `sellout`, `tipe fokus`, `vast input`, `vast closing`
- visiting dashboard dan detail promotor juga perlu compare week-to-week

Kemungkinan file:
- [sellout_insight_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/sellout_insight_page.dart)
- [sell_out_summary_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/pages/sell_out/sell_out_summary_page.dart)
- [visiting_dashboard_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/pages/visiting/visiting_dashboard_page.dart)
- [pre_visit_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/pages/visiting/pre_visit_page.dart)

### 6. Target Harian Promotor dari Home Sator

Permintaan user:
- sebelum kirim ke grup harus ada konfirmasi
- ada preview card
- target bisa diedit dulu
- card minimal berisi:
  - nama promotor
  - target all type harian
  - target vast harian
  - target produk fokus harian

Area yang perlu dicek:
- home harian sator
- kemungkinan chat send-card flow

## Risiko / Hal yang Harus Dijaga

- worktree sedang dirty dan ada agent lain aktif
- area `jadwal` dan `grup admin` sengaja di-skip sesuai arahan user
- file `chat`, `sell_out`, dan `stock_input` sudah dirty, jadi sebelum edit wajib baca diff dulu
