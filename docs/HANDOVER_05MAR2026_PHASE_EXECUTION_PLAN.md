# HANDOVER AGENT - 05 Mar 2026 (Phase Execution Plan)

## Tujuan Dokumen
Dokumen ini jadi acuan eksekusi lintas agent untuk pekerjaan lanjutan SATOR, Promotor, AllBrand, dan Chat integration agar tidak terjadi overlap atau kebingungan scope.

## Ringkasan Status Saat Ini
- MCP Supabase: sudah terkonfigurasi mode bearer token (perlu env `SUPABASE_ACCESS_TOKEN` aktif di session saat eksekusi).
- AllBrand promotor: riwayat harian/bulanan + market share sudah ditambahkan di halaman laporan AllBrand.
- AllBrand di chat room toko: panel performa toko sudah membaca snapshot allbrand + history 7 hari dan auto refresh realtime.
- SATOR dashboard phase awal: duplikasi menu Sellout/Laporan sudah dibersihkan di quick access, tab `Tim` dihapus dari halaman laporan lama, card harian/bulanan dirombak, header dipadatkan.
- Bug runtime `Future.catchError` pada SATOR home: sudah dipatch dengan helper type-safe (`try/catch` + safe parser).

---

## Phase 1 - Stabilization + Struktur Navigasi (SATOR)
Status: **DONE (core)**, **POLISH tersisa**

### Scope
1. Rapikan dashboard SATOR (header, card utama, KPI card behavior).
2. Hilangkan duplikasi akses Sellout vs Laporan (fokus ke `Laporan`).
3. Pastikan card Harian/Bulanan klik ke halaman laporan yang benar.

### Sudah Dikerjakan
1. Header SATOR: tampil nama lebih clean, kartu total toko/promotor lama dihapus.
2. Label bottom nav menjadi `Laporan`.
3. Tab `Tim` di modul laporan lama dihapus.
4. Quick access item ganda menuju sellout lama dihapus.
5. Card KPI diarahkan ke menu KPI & Bonus.
6. Perbaikan crash `catchError` yang menyebabkan data dashboard gagal load.

### Sisa Minor
1. Visual card masih dianggap “kaku” oleh user, perlu redesign UI phase berikutnya.
2. Verifikasi nama SATOR hilang sudah aman di semua akun (butuh test beberapa user).

### Definisi Selesai (DoD)
1. Tidak ada menu duplikat Sellout/Laporan di entry utama.
2. Data home SATOR tidak error runtime.
3. Card harian/bulanan menavigasi ke halaman laporan, bukan route legacy.

---

## Phase 2 - Redesign Halaman Laporan SATOR + Reports Sellout Tim
Status: **IN PROGRESS (MAYORITAS IMPLEMENTASI SUDAH MASUK)**

### Update 06 Mar 2026 (Progress Aktual Kode)
Sudah dikerjakan:
1. Menu `Reports Sellout Tim` sudah aktif di Workplace + route khusus (`/sator/reports-sellout-tim`).
2. Halaman `Laporan` sudah berisi tab `Leaderboard`, `Live Feed`, `Reports Sellout Tim`.
3. Modul `Reports Sellout Tim` sudah punya tab `Daily`, `Weekly`, `Monthly` + filter toko.
4. Daily report sudah menampilkan member tidak jualan + ringkasan total/target/fokus.
5. Ringkasan tipe produk fokus (nama tipe + unit) sudah ditampilkan di footer Daily.
6. Header atas laporan sudah menampilkan info identitas SATOR, area, dan SPV.
7. Weekly report sudah membaca `weekly_targets` dari DB admin (fallback hardcoded hanya jika tabel kosong).

Sisa final sebelum ditandai DONE:
1. Validasi parity data FE-BE via query audit (`20260305_promotor_sator_parity_audit.sql`) untuk minimal 2 tanggal.
2. QA manual device untuk Daily/Weekly/Monthly + Live Feed (termasuk foto upload terbaru).
3. Polish minor UI sesuai feedback user (spacing/typography jika masih dirasa padat).

### Scope Inti
1. Redesign halaman `Laporan` agar compact dan mudah scan.
2. Buat menu baru `Reports sellout tim` dengan tab:
   - Daily
   - Weekly
   - Monthly
3. Pusatkan kebutuhan rekap team untuk SATOR pada menu baru ini.

### Requirement Detail
1. Header/tab laporan:
   - perbaiki kontras teks tab agar terbaca jelas
   - hapus duplikasi tampilan tanggal/hari
   - pindahkan info kupang/SPV ke area header atas
2. Leaderboard:
   - lebih compact
   - nama SATOR (leader) lebih menonjol
   - nama promotor lebih kecil
3. Live feed:
   - redesign modern, bukan layout lama
4. Hapus tab `Tim` (sudah dilakukan), gantikan oleh menu baru khusus `Reports sellout tim`.

### Requirement per Tab (Reports sellout tim)
1. Daily:
   - list promotor + toko + nominal + tipe terjual
   - tetap tampilkan anggota yang tidak jualan
   - footer ringkasan: total hari ini, target hari ini, persen
   - ringkasan produk fokus: tipe fokus apa, total unit
   - filter per toko
2. Weekly:
   - struktur mirip Daily tapi refer ke target weekly dari Admin
   - tampil kurang/lebih dari target per orang per minggu
   - detail week 1/2/3/4
   - filter per toko + filter bulan
3. Monthly:
   - rekap detail per orang
   - bisa filter per toko
   - filter bulan/tanggal
   - mencakup all type + produk fokus

### Dependency Teknis
1. Pastikan source target weekly dari modul Admin (jangan hardcode FE).
2. Validasi rule “2 hitung 1” hanya untuk produk tertentu.
3. Sinkron field target/achievement alltype vs focus dengan RPC existing.

### Definisi Selesai (DoD)
1. Menu `Reports sellout tim` aktif dan bisa dipakai SATOR end-to-end.
2. Daily/Weekly/Monthly punya data + filter + summary yang konsisten.
3. Weekly terbaca langsung dari pengaturan admin.

---

## Phase 3 - Penyempurnaan Dashboard SATOR (UI + Data Akurat)
Status: **IN PROGRESS (CORE IMPLEMENTATION SUDAH MASUK)**

### Update 06 Mar 2026 (Progress Aktual Kode)
Sudah dikerjakan:
1. Card Harian/Bulanan dashboard SATOR dipoles (visual lebih clean, CTA lebih jelas).
2. Perhitungan target harian tidak lagi hardcoded `30 hari`, sekarang dinamis sesuai jumlah hari di bulan berjalan.
3. Fallback revenue dari RPC legacy pada dashboard dihapus; achievement harian/bulanan mengacu query transaksi DB.
4. Resolusi target per promotor diperbaiki pakai `updated_at` terbaru agar tidak ambil target lama.
5. Klik card Bulanan diarahkan ke `Reports Sellout Tim` tab `Monthly` (`?tab=monthly`), bukan route ambigu.
6. Jika target belum diset Admin, dashboard tampilkan notice eksplisit agar tidak terbaca sebagai “angka nol palsu”.

Sisa final sebelum ditandai DONE:
1. QA multi akun SATOR untuk validasi angka harian/bulanan vs data laporan.
2. Uji UX klik card harian/bulanan di device low-end (cek jank + nav consistency).
3. Konfirmasi visual final dengan user (approval desain card).

### Scope
1. Redesign visual card dashboard agar tidak kaku.
2. Pastikan card Penjualan Harian/Bulanan 100% berbasis database (bukan placeholder).
3. Validasi fallback data ketika RPC kosong.

### Requirement
1. Card harian:
   - `Target harian / Total penjualan harian + persen`
   - `Target harian produk fokus / Pencapaian + persen`
2. Card bulanan:
   - `Target bulanan / Pencapaian + persen`
   - `Target fokus bulanan / Pencapaian + persen`
3. Klik card:
   - Harian -> menu Laporan
   - Bulanan -> halaman laporan akumulasi bulanan
4. KPI bulanan:
   - bobot dinamis (komponen kosong harus auto normalisasi)
   - klik ke menu KPI & Bonus

### Definisi Selesai (DoD)
1. Angka tidak nol palsu saat data transaksi sudah ada.
2. Nama SATOR selalu tampil stabil.
3. User menyetujui kualitas visual card baru.

---

## Phase 4 - Promotor UX Flow (Stok + Bonus + Header)
Status: **PENDING**

### Scope
1. Sederhanakan input stok promotor agar cepat dan tidak panjang.
2. Rapikan header promotor (nama 1 baris, notif tidak memotong nama).
3. Rapikan estimasi bonus dan riwayat transaksi (termasuk rule 2 hitung 1 pada produk tertentu).
4. Gabungkan `Validasi stok` ke menu `Stok saya`.
5. Ubah `Cari stok` menjadi `Stok saya`:
   - default stok toko miliknya
   - tetap ada fitur cari stok area SATOR dari halaman yang sama

### Requirement Detail
1. Estimasi bonus:
   - range harga dihapus
   - riwayat dibuat lebih compact
   - filter tanggal tersedia
2. Stok saya:
   - grouping per tipe
   - tampil IMEI + qty
   - tetap cepat diakses (minim scrolling panjang)

### Definisi Selesai (DoD)
1. Promotor bisa input dan cek stok lebih cepat dari flow sebelumnya.
2. Rule bonus “2 hitung 1” terimplementasi sesuai daftar produk yang ditentukan admin/sistem.
3. Satu menu stok meng-cover validasi + pencarian + stok toko sendiri.

---

## Checklist Eksekusi Agent Berikutnya
1. Kerjakan Phase 2 lebih dulu sampai usable.
2. Setelah setiap subfitur selesai, jalankan:
   - `flutter format` pada file terkait
   - `flutter analyze` minimal per file yang disentuh
3. Catat setiap perubahan ke handover baru (`HANDOVER_XXMAR2026_...md`) dengan format:
   - apa yang berubah
   - file yang disentuh
   - query/RPC/migration yang terlibat
   - hasil validasi
4. Jangan ubah rule bisnis weekly/focus/2-hitung-1 tanpa referensi ke modul admin/aturan sistem.

## Catatan Risiko
1. Data nol di dashboard biasanya akibat mapping field RPC berbeda nama; cek payload mentah dulu sebelum mapping FE.
2. Banyak fallback bisa menutupi bug source data, jadi log debug sementara tetap dibutuhkan sampai phase stabil.
3. Hindari route lama (`sellout`) jika route baru (`laporan`) sudah jadi sumber utama.
