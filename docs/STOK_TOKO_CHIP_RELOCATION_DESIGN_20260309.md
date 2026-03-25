# Stok Toko, Validasi Harian, Relokasi IMEI, dan Barang Chip

Dokumen ini adalah handoff final untuk pekerjaan lanjutan terkait:

- validasi stok harian promotor
- tampilan `Stok Toko`
- relokasi stok antar toko berbasis IMEI
- perubahan status `fresh -> chip` dengan approval sator
- pengecualian barang chip dari penjualan normal, bonus, dan leaderboard
- penyeragaman label produk `5G` agar menempel ke nama produk

Tanggal ringkasan: 9 Maret 2026

## 1. Tujuan Bisnis

Promotor wajib mengetahui stok fisik toko setiap hari. Validasi harian adalah proses promotor mengecek stok fisik di rak agar stok operasional toko tetap akurat.

Hasil akhir yang diinginkan:

- `Validasi` menjadi pintu utama stok harian.
- `Stok Toko` menjadi tampilan stok operasional setelah promotor melakukan pengecekan.
- Jika ada selisih, promotor bisa langsung:
  - menambah stok baru
  - claim IMEI pindahan dari toko lain
  - melaporkan stok keluar dari toko
  - mengajukan perubahan status `fresh -> chip`
- Barang `chip` tetap terlacak, tetapi tidak ikut ranking penjualan normal dan bonus.

## 2. Keputusan Final Yang Sudah Disepakati

### 2.1 Validasi Harian

- Validasi dilakukan setiap hari oleh promotor.
- `Stok tersedia` diganti nama menjadi `Stok Toko`.
- Menu `Stok Toko` untuk promotor harus menjadi 2 sub tab:
  - `Validasi`
  - `Stok Toko`
- Setelah validasi, promotor tetap bisa melihat `Stok Toko` yang sesuai operasional hari tersebut.
- Untuk histori tanggal lampau, user melihat data tanggal itu.
- Untuk hari ini, stok boleh tetap berubah live jika ada stok masuk atau perpindahan di hari yang sama.

### 2.2 Selisih Stok Saat Validasi

#### Jika stok fisik lebih banyak daripada data sistem

- Jika IMEI benar-benar baru, promotor boleh input stok baru.
- Jika IMEI sudah pernah ada di sistem dan sedang tidak melekat ke toko mana pun:
  - sistem menawarkan claim stok pindahan
  - sistem tidak membuat stok baru
  - sistem hanya memindahkan lokasi stok existing

Aturan inti:

- 1 IMEI = 1 stok
- IMEI lama tidak boleh dibuat jadi stok baru kedua kalinya

#### Jika stok fisik lebih sedikit daripada data sistem

- Promotor bisa long press item lalu pilih aksi lapor stok keluar / pindah.
- Promotor tidak wajib tahu toko tujuan.
- Stok dikeluarkan dari toko lama dan menunggu di-claim toko penerima.
- Keputusan final:
  - `store_id = null`
  - `promotor_id = null`
  - stok masuk status menunggu claim

### 2.3 Claim Stok Pindahan

- Claim terjadi saat promotor toko penerima scan IMEI pada input stok.
- Jika IMEI ditemukan sebagai stok existing dengan `store_id = null`, sistem menawarkan pindah ke toko penerima.
- Sistem tidak membuat stok baru.
- Sistem mengubah lokasi stok existing.

### 2.4 Status Chip

- Stok baru bisa langsung diinput sebagai `chip`.
- Ubah status manual untuk user umum hanya berlaku `fresh -> chip`.
- Promotor mengajukan request chip.
- Approval wajib oleh sator.
- Alasan chip wajib diisi.
- `chip -> fresh` tidak perlu dibuat untuk user umum.
- Koreksi balik jika suatu saat dibutuhkan cukup ditangani admin.

### 2.5 Penjualan Barang Chip

Barang chip:

- tetap boleh diproses di `sales_sell_out`
- tetapi:
  - tidak menambah penjualan normal
  - tidak menambah ranking
  - bonus = 0

Alasan bisnis:

- barang chip dianggap pernah terjual sebelumnya
- scan ulang dilakukan karena kebutuhan operasional

### 2.6 Visibilitas Label Chip

Label chip hanya boleh diketahui oleh:

- promotor owner / pelapor
- sator terkait
- spv terkait
- admin

Tidak perlu diketahui oleh:

- manager
- user umum lain pada leaderboard normal

Pembatasan ini harus konsisten di:

- leaderboard
- live feed
- export
- detail penjualan yang terkait leaderboard

### 2.7 Label Produk 5G

Label `5G` harus menempel ke nama produk.

Format target:

- `V50 5G`
- `V60 5G`

Bukan model name lalu badge `5G` yang terpisah jauh.

## 3. Ringkasan Sistem Existing Saat Dokumen Ini Ditulis

### 3.1 Yang Sudah Ada

- Tabel `stok` sudah punya:
  - `tipe_stok`
  - `chip_reason`
  - `chip_approved_by`
  - `chip_approved_at`
- Tabel `stock_movement_log` sudah ada dan cocok untuk audit perpindahan.
- Input stok promotor sudah mendukung tipe:
  - `fresh`
  - `chip`
  - `display`
- Ada halaman existing yang relevan:
  - [stok_toko_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stok_toko_page.dart)
  - [stock_validation_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stock_validation_page.dart)
  - [input_stok_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/input_stok_page.dart)
  - [stock_input_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stock_input_page.dart)
  - [sell_out_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/sell_out_page.dart)
  - [leaderboard_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/leaderboard_page.dart)
  - [sator_sales_tab.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/tabs/sator_sales_tab.dart)
  - [admin_stock_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/admin/presentation/pages/admin_stock_page.dart)

### 3.2 Yang Belum Ada / Belum Lengkap

- request chip dengan approval sator yang terhubung ke UI
- flow relokasi stok yang rapi
- penanda penjualan chip di `sales_sell_out`
- pembatasan label chip di leaderboard/feed/export
- UI claim IMEI pindahan
- UI lapor stok keluar
- UI ringkasan chip per toko
- penyeragaman label `5G` di seluruh halaman utama

## 4. Scope File Yang Harus Dianggap Touchpoint

Bagian ini sengaja eksplisit agar agent berikut tidak perlu mencari ulang file utama.

### 4.1 Promotor

- [stok_toko_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stok_toko_page.dart)
  - saat ini sudah punya logika tanggal, validasi, dan stock snapshot
  - perlu dipecah jelas menjadi sub tab `Validasi` dan `Stok Toko`
  - perlu action long press untuk lapor stok keluar dan request chip
  - perlu ringkasan barang chip
- [stock_validation_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stock_validation_page.dart)
  - halaman validasi existing
  - perlu diputuskan apakah dipertahankan sebagai halaman terpisah atau digabung ke `StokTokoPage`
- [input_stok_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/input_stok_page.dart)
  - perlu flow claim IMEI pindahan saat scan/input IMEI
- [stock_input_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/stock_input_page.dart)
  - cek apakah ini jalur aktif atau legacy duplikat dari `input_stok_page.dart`
  - jangan implementasi dua kali tanpa audit route
- [sell_out_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/sell_out_page.dart)
  - perlu tandai `is_chip_sale`
  - perlu bonus 0 untuk chip sale
  - perlu filter visibilitas label chip
- [leaderboard_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/promotor/presentation/pages/leaderboard_page.dart)
  - perlu mengecualikan chip sale dari ranking normal
  - jangan bocorkan label chip ke role yang tidak berhak

### 4.2 Sator

- [sator_sales_tab.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/sator/presentation/tabs/sator_sales_tab.dart)
  - touchpoint utama feed dan leaderboard sator
  - harus ikut filter chip sale dari ranking normal
  - role sator tetap boleh lihat label chip untuk timnya
- halaman approval chip untuk sator belum terlihat ada
  - kemungkinan perlu file baru

### 4.3 Admin / SPV

- [admin_stock_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/admin/presentation/pages/admin_stock_page.dart)
- [stock_rules_page.dart](/home/geger/Documents/project%20APK/project%20vivo%20apk/lib/features/admin/presentation/pages/stock_rules_page.dart)
- halaman SPV terkait stok / audit penjualan chip perlu diaudit saat fase akhir

### 4.4 Backend

- [20260309_stock_chip_relocation_flow.sql](/home/geger/Documents/project%20APK/project%20vivo%20apk/supabase/migrations/20260309_stock_chip_relocation_flow.sql)
- RPC leaderboard/feed yang sudah dipakai UI:
  - `get_leaderboard_feed`
  - `get_live_feed`
  - `get_team_live_feed`
  - `get_team_leaderboard`
  - `get_sator_leaderboard`

## 5. Kontrak Data Final

Bagian ini adalah kontrak yang harus dianggap final kecuali ada keputusan baru dari user.

### 5.1 Tabel `stok`

Field baru / perilaku final:

- `relocation_status`
  - `assigned`
  - `pending_claim`
- `relocation_note`
- `relocation_reported_by`
- `relocation_reported_at`
- `pending_chip_reason`
- `chip_requested_by`
- `chip_requested_at`

Makna:

- `assigned`: stok aktif melekat ke toko tertentu
- `pending_claim`: stok sudah dikeluarkan dari toko lama dan menunggu toko penerima claim

Kontrak perilaku:

- stok pending claim harus `store_id = null`
- stok pending claim harus `promotor_id = null`
- IMEI pending claim tidak boleh diinsert sebagai stok baru
- stock existing yang sudah `is_sold = true` tidak boleh direlokasi atau di-claim

### 5.2 Tabel `stock_chip_requests`

Field minimum:

- `stok_id`
- `store_id`
- `promotor_id`
- `sator_id`
- `reason`
- `status`
  - `pending`
  - `approved`
  - `rejected`
- `requested_at`
- `approved_at`
- `approved_by`
- `rejection_note`

Kontrak perilaku:

- hanya stok `fresh` yang boleh diajukan menjadi chip
- request chip wajib punya reason
- request chip aktif harus dianggap pending sampai ada keputusan sator
- jika approved:
  - `stok.tipe_stok = chip`
  - `stok.chip_reason` terisi
  - `stok.chip_approved_by` terisi
  - `stok.chip_approved_at` terisi
- jika rejected:
  - `stok.tipe_stok` tetap `fresh`
  - pending field di stok dibersihkan

### 5.3 Tabel `sales_sell_out`

Field tambahan:

- `stok_id`
- `is_chip_sale`
- `chip_label_visible`

Makna final:

- `is_chip_sale = true` bila transaksi berasal dari stok `tipe_stok = chip`
- `chip_label_visible` bukan izin global, tetapi flag payload / presentasi untuk role yang memang berhak melihat label chip

Kontrak perilaku:

- transaksi chip tetap disimpan
- chip sale tetap bisa masuk histori transaksi
- chip sale tidak boleh menambah penjualan normal, ranking, bonus, atau leaderboard

### 5.4 Tabel `stock_validations`

Harus menyimpan:

- `store_id`

Karena validasi harus selalu jelas melekat ke toko tertentu.

## 6. Kontrak RPC Final

### 6.1 `report_stock_moved_out(p_stok_id, p_note)`

Tujuan:

- mengeluarkan stok dari toko lama
- menjadikan stok menunggu claim

Perilaku final:

- valid hanya untuk stok existing yang belum sold
- set:
  - `store_id = null`
  - `promotor_id = null`
  - `relocation_status = pending_claim`
  - metadata relokasi terisi
- wajib menulis audit ke `stock_movement_log`

### 6.2 `claim_relocated_stock(p_imei, p_variant_id, p_note)`

Tujuan:

- memindahkan stok existing pending claim ke toko promotor saat ini

Perilaku final:

- mencari stock existing dengan:
  - `imei = p_imei`
  - `store_id is null`
  - `relocation_status = pending_claim`
  - `is_sold = false`
- jika ketemu:
  - update store ke toko promotor aktif
  - update promotor owner
  - ubah status ke `assigned`
  - tulis audit movement
- tidak boleh insert stok baru

### 6.3 `submit_chip_request(p_stok_id, p_reason)`

Tujuan:

- membuat request chip untuk stok `fresh`

Perilaku final:

- reason wajib
- hanya stok `fresh` yang bisa diajukan
- menyimpan request pending
- mengisi pending metadata di tabel `stok`

### 6.4 `review_chip_request(p_request_id, p_action, p_rejection_note)`

Tujuan:

- approve / reject request chip oleh sator

Perilaku final:

- `p_action` hanya `approved` atau `rejected`
- jika approved:
  - stok menjadi `chip`
  - pending metadata dibersihkan
  - movement log dicatat
- jika rejected:
  - stok tetap `fresh`
  - pending metadata dibersihkan

### 6.5 `get_store_chip_summary(p_store_id)`

Tujuan:

- memberikan ringkasan barang chip per toko

Payload minimal yang harus tersedia:

- total chip
- daftar IMEI chip
- nama produk
- network type
- varian
- warna
- kapan dichip
- oleh siapa
- alasan chip

## 7. Flow Operasional Final

### 7.1 Validasi Harian Promotor

Flow target:

1. Promotor buka menu `Stok Toko`.
2. Sub tab default adalah `Validasi`.
3. List validasi menampilkan stok IMEI-level aktif untuk toko promotor.
4. Promotor mengecek fisik rak.
5. Promotor centang / submit item yang memang ada.
6. Setelah validasi, promotor bisa pindah ke sub tab `Stok Toko`.

Action tambahan yang harus tersedia dari area validasi:

- input stok baru
- claim IMEI pindahan
- lapor stok keluar
- ajukan chip untuk item `fresh`

### 7.2 Input Stok Baru / Claim IMEI Lama

Saat promotor scan IMEI:

#### Jika IMEI belum ada di sistem

- lanjut input stok baru seperti biasa

#### Jika IMEI ada di toko lain dan masih aktif

- tolak input
- tampilkan pesan stok sudah ada di sistem

#### Jika IMEI ada di sistem tetapi `store_id = null` dan `relocation_status = pending_claim`

- tampilkan dialog claim
- jika user setuju:
  - panggil `claim_relocated_stock`
  - jangan insert stok baru

### 7.3 Lapor Stok Keluar

Promotor long press item validasi yang fisiknya sudah tidak ada.

Flow:

1. pilih `Lapor stok keluar`
2. isi alasan
3. konfirmasi
4. sistem memanggil `report_stock_moved_out`
5. stok keluar dari toko lama dan menunggu claim toko baru

### 7.4 Request Chip

Promotor long press item `fresh`.

Flow:

1. pilih `Ajukan jadi chip`
2. isi alasan wajib
3. submit
4. sistem membuat request pending
5. sator melihat request pending
6. sator approve / reject

### 7.5 Sell Out Barang Chip

Saat sell out:

1. sistem lookup stok dari IMEI
2. jika `tipe_stok = chip`
   - transaksi tetap disimpan
   - `is_chip_sale = true`
   - bonus = 0
   - tidak ikut ranking normal

## 8. Matrix Hak Akses Final

- promotor
  - bisa validasi stok harian
  - bisa input stok baru
  - bisa claim stok pindahan
  - bisa lapor stok keluar
  - bisa ajukan chip
  - bisa melihat label chip hanya untuk stok / transaksi miliknya sendiri
- sator
  - bisa melihat request chip dari tim
  - bisa approve / reject request chip
  - bisa melihat label chip untuk timnya
- spv
  - view only untuk ringkasan chip, audit chip, dan penjualan chip area terkait
  - tidak approve chip
- admin
  - bisa melihat semua data chip dan audit relokasi
  - bisa melakukan koreksi jika nanti dibutuhkan
- manager
  - tidak perlu melihat label chip di leaderboard normal atau feed umum

## 9. Acceptance Criteria Yang Harus Dipenuhi

### 9.1 Validasi

- Jika promotor membuka hari ini, item aktif toko yang belum divalidasi muncul di tab `Validasi`.
- Jika promotor membuka tanggal lampau, histori tanggal itu tampil konsisten dan tidak memakai pending live hari ini.
- Setelah validasi sebagian item, item yang sudah tervalidasi tidak lagi muncul di pending hari yang sama.

### 9.2 Relokasi

- Jika promotor scan IMEI lama dengan `store_id = null` dan `relocation_status = pending_claim`, sistem menawarkan claim ke toko saat ini.
- Claim IMEI pindahan tidak membuat row `stok` baru.
- Jika IMEI masih aktif di toko lain, sistem menolak input stok baru.
- Jika promotor lapor stok keluar, stok menjadi tidak melekat ke toko mana pun dan siap di-claim toko baru.

### 9.3 Chip

- Hanya stok `fresh` yang bisa diajukan jadi chip.
- Request chip tanpa alasan harus ditolak.
- Approval sator mengubah `tipe_stok` menjadi `chip`.
- Rejection tidak mengubah `tipe_stok`.
- Riwayat request chip tetap tersimpan.

### 9.4 Sell Out dan Leaderboard

- Jika sale berasal dari stok chip, transaksi tetap tersimpan.
- Jika sale berasal dari stok chip, bonus transaksi harus 0.
- Chip sale tidak boleh ikut ranking atau leaderboard normal.
- Leaderboard umum tidak boleh menampilkan label chip ke role yang tidak berhak.
- Admin, SPV area terkait, Sator terkait, dan promotor owner tetap bisa melihat label chip bila memang konteksnya detail internal.

### 9.5 5G Label

- Nama produk di area utama harus tampil sebagai satu string final, misalnya `V50 5G`.
- Jangan tampilkan `5G` sebagai badge jauh terpisah dari model name pada halaman stok, validasi, sell out, leaderboard, dan feed terkait produk.

## 10. Edge Case dan Perilaku Fallback

- Jika promotor belum punya assignment toko aktif, semua flow promotor yang butuh store harus gagal dengan pesan jelas.
- Jika stok sudah sold, stok tidak boleh direlokasi, di-claim, atau diajukan chip lagi.
- Jika ada request chip pending kedua untuk stok yang sama, implementasi harus mencegah duplikasi request aktif.
- Jika request chip di-review dua kali, backend harus menolak atau mengunci review kedua.
- Jika claim menemukan variant mismatch, backend harus menolak claim.
- Jika histori validasi tanggal lampau belum punya snapshot memadai, UI harus jelas membedakan data validated vs live fallback.

## 11. Keputusan Final vs Asumsi Implementasi

### 11.1 Keputusan Final

- `store_id = null` dipakai untuk stok keluar sementara yang menunggu claim.
- claim stok dilakukan saat scan/input stok, bukan saat penjualan.
- hari ini tetap boleh live dan berubah real-time.
- histori tanggal lampau harus merefer ke data tanggal itu.
- chip sale tersimpan sebagai transaksi audit tetapi dikeluarkan dari ranking dan bonus normal.

### 11.2 Asumsi Implementasi Yang Masih Perlu Dicek Saat Coding

- apakah `stock_validation_page.dart` akan digabung ke `stok_toko_page.dart` atau tetap dipisah
- apakah `stock_input_page.dart` masih aktif atau hanya legacy duplikat
- taxonomy final `stock_movement_log.movement_type`
- RPC leaderboard/feed mana saja yang perlu diubah di database agar chip sale benar-benar terfilter
- bagaimana payload `chip_label_visible` terbaik dipakai: sebagai field persisted atau murni hasil shaping response

## 12. Audit Migration Draft Yang Sudah Ada

File draft yang sudah ada:

- [20260309_stock_chip_relocation_flow.sql](/home/geger/Documents/project%20APK/project%20vivo%20apk/supabase/migrations/20260309_stock_chip_relocation_flow.sql)

Yang sudah tercakup di draft:

- penambahan `store_id` pada `stock_validations`
- field relokasi pada `stok`
- tabel `stock_chip_requests`
- field `stok_id`, `is_chip_sale`, `chip_label_visible` pada `sales_sell_out`
- RPC:
  - `report_stock_moved_out`
  - `claim_relocated_stock`
  - `submit_chip_request`
  - `review_chip_request`
  - `get_store_chip_summary`

Gap / catatan audit yang harus diperhatikan agent berikut:

- draft migration belum otomatis berarti UI sudah terhubung
- pencarian repo saat dokumen dibuat belum menemukan pemakaian RPC baru di layer Flutter
- `report_stock_moved_out` saat ini masih menulis `movement_type = 'adjustment'`
  - ini perlu dipastikan apakah taxonomy final memang `adjustment` atau seharusnya `transfer_out` / `relocation_out`
- `review_chip_request` perlu diaudit lagi agar enforcement approval tidak hanya bergantung pada RLS, tetapi juga tervalidasi aman di function body
- belum ada proteksi eksplisit yang terlihat untuk mencegah request chip pending ganda untuk stok yang sama
- belum ada update ke RPC leaderboard/feed existing untuk mengecualikan `is_chip_sale = true`
- belum ada update sell out flow Flutter untuk menandai chip sale saat submit transaksi

## 13. Urutan Implementasi Yang Direkomendasikan

### Fase 1 - Amankan Fondasi

- review migration draft
- cocokkan dengan schema aktif
- perjelas taxonomy movement log
- tutup gap validasi function backend

### Fase 2 - Promotor

- rapikan `Stok Toko` menjadi tab `Validasi` dan `Stok Toko`
- tambah dialog lapor stok keluar
- tambah dialog request chip
- tambah claim IMEI pindahan di input stok
- rapikan label `5G`

### Fase 3 - Sator

- buat halaman approval chip
- tampilkan request pending tim
- tampilkan ringkasan chip per toko

### Fase 4 - Sell Out dan Leaderboard

- tandai chip sale saat sell out
- bonus 0 untuk chip sale
- filter chip sale dari ranking/feed normal
- batasi visibilitas label chip

### Fase 5 - SPV, Admin, Export

- tampilkan summary chip
- tampilkan audit chip dan audit relokasi
- samakan aturan visibilitas label chip di export dan dashboard

## 14. Next Step Paling Aman Saat Melanjutkan Kerja

Urutan lanjut yang direkomendasikan:

1. review [20260309_stock_chip_relocation_flow.sql](/home/geger/Documents/project%20APK/project%20vivo%20apk/supabase/migrations/20260309_stock_chip_relocation_flow.sql)
2. cek schema aktif agar migration tidak bentrok
3. audit route promotor untuk menentukan halaman input stok yang aktif
4. update flow promotor lebih dulu
5. buat approval chip sator
6. baru update sell out, leaderboard, dan feed

Dokumen ini harus dipakai sebagai pegangan utama handoff. Jika ada konflik antara implementasi lama dan dokumen ini, anggap dokumen ini sebagai keputusan bisnis terbaru sampai user memberi keputusan baru.
