# Product Decisions Locked

Dokumen ini berisi keputusan produk yang sudah ditetapkan user.  
Dokumen ini bukan tempat brainstorming.  
Dokumen ini adalah pagar kerja untuk agent, developer, schema, RPC, dan UI.

## Aturan kerja

- Yang tertulis di dokumen ini dianggap `Keputusan Tetap`.
- Agent tidak boleh mengubah keputusan ini tanpa konfirmasi user.
- Jika ada area yang belum tertulis, statusnya `Belum Diputuskan`.
- Jika code lama bertentangan dengan dokumen ini, ikuti dokumen ini.

## Scope rollout

- Area awal yang dibangun adalah `Kupang`.
- Area kabupaten dan Sumba nanti mengikuti pola Kupang.
- Ranking, monitoring, dan struktur awal dibatasi pada konteks area Kupang dulu.

## Role final

Role resmi:

- `admin`
- `manager`
- `spv`
- `trainer`
- `sator`
- `promotor`

## Struktur hierarchy

Hierarchy utama:

- `Manager -> SPV -> SATOR -> Promotor`

Posisi trainer:

- `Trainer` berdiri paralel
- `Trainer` membina langsung `Promotor`

Hak trainer:

- boleh melihat performa promotor yang bukan binaannya
- akses performa trainer difokuskan ke:
  - `Sell Out`
  - `Produk Fokus`

## Menu utama semua role

Bottom navigation utama harus sama untuk semua role:

- `Home`
- `Workplace`
- `Ranking`
- `Chat`
- `Profil`

Aturan:

- tidak boleh ada role yang punya label bottom nav berbeda
- fitur tambahan dimasukkan ke dalam `Workplace`

## Struktur Home

Home tiap role maksimal `5 blok utama`.

Home tidak boleh terlalu ramai.  
Penjelasan panjang tidak ditaruh langsung di body utama.  
Kalau perlu penjelasan, tampilkan lewat titik bantu kecil atau halaman/detail klik.

### Promotor Home

Fokus utama:

- target `Harian`
- target `Mingguan`
- target `Bulanan`
- bonus
- aktivitas
- ranking area SPV

### SATOR Home

Harus menampilkan target utama:

- `Sell Out All Type`
- `Produk Fokus`
- `Sell In`

`Sell In` juga utama dan harus tampil di dashboard.

### SPV Home

Harus menampilkan target utama:

- `Sell Out All Type`
- `Produk Fokus`
- `Sell In`

SPV home berfungsi untuk memantau kerja SATOR dan tim di bawahnya.

### Trainer Home

Trainer dikerjakan paling terakhir.

Fokus trainer:

- `Produk Fokus`
- data produk
- bahan training promotor

KPI trainer belum diputuskan final.

### Manager Home

Dua fokus sama-sama penting:

- kontrol struktur dan kerja SPV
- ringkasan pencapaian bisnis

## Struktur Workplace

Workplace adalah kumpulan menu kerja yang dikelompokkan per kategori sesuai role.

Workplace bukan tempat semua fitur dicampur tanpa struktur.

### Promotor Workplace

Harus dikelompokkan agar promotor mudah kerja harian.

Fokus isi:

- `Sell Out`
- bonus milik promotor
- rangkuman aktivitas promotor
- semua aktivitas penting yang harus dikerjakan setiap hari

### SATOR Workplace

Harus ada:

- `Visiting`
- monitoring `Sell Out`
- monitoring `Sell In`

### SPV Workplace

Harus bisa monitor kerja SATOR:

- `Sell Out`
- `Sell In`
- `Visiting`
- `Approval`
- progress pekerjaan
- nyangkut di siapa

### Trainer Workplace

Trainer harus punya:

- data produk
- komparasi produk antar brand
- fitur unggulan produk
- materi yang bisa dipakai untuk training promotor

Promotor juga bisa belajar dari data ini.

### Manager Workplace

Manager harus bisa:

- kontrol kerja SPV
- lihat pencapaian SPV
- turun melihat detail semua level di bawahnya

### Admin Workplace

Admin harus bisa kelola semua role:

- tambah manager
- tambah trainer
- tambah SPV
- tambah SATOR
- tambah promotor

## Ranking per role

Makna `Ranking`:

- urutan performa dari terbaik sampai terjelek

### Promotor Ranking

- ranking promotor di area Kupang dulu

### SATOR Ranking

SATOR melihat:

- ranking `SATOR`
- ranking `Promotor`

Konteks promotor:

- semua promotor di bawah SPV yang sama

Tujuan:

- ada kompetisi antar SATOR

### SPV Ranking

SPV melihat:

- ranking `SATOR`
- ranking `Promotor`

### Trainer Ranking

Trainer melihat:

- ranking `Promotor`

### Manager Ranking

Manager melihat:

- ranking `SPV`
- ranking `SATOR`
- ranking `Promotor`

Manager ranking bukan ranking untuk dirinya sendiri.  
Manager ranking adalah pusat pantau semua level di bawahnya.

## Vocabulary bisnis yang sudah diputuskan

### Domain target sell out

Struktur resmi:

- `Target Sell Out`
- `Target Sell Out All Type`
- `Target Produk Fokus`
- `Detail Tipe Khusus`

Makna:

- `Target Sell Out` adalah domain induk
- `All Type` dan `Produk Fokus` adalah dua cabang utama
- `Tipe Khusus` adalah turunan dari `Produk Fokus`

### Produk Fokus

- ditetapkan per bulan
- bisa berbeda setiap bulan

### Tipe Khusus

- subset dari `Produk Fokus`
- punya target khusus sendiri
- contoh:
  - produk fokus ada 5 tipe
  - tipe khusus hanya 3 tipe

## Target per role

### Promotor

Target promotor:

- `Sell Out All Type`
- `Produk Fokus`

### SATOR

Target SATOR:

- `Sell Out All Type`
- `Produk Fokus`
- `Sell In`

### SPV

Target SPV:

- sama seperti SATOR
- `Sell Out All Type`
- `Produk Fokus`
- `Sell In`

### Trainer

Target trainer belum final.  
Fokus sementara trainer ada di `Produk Fokus`.

## Best Performance otomatis

Setiap malam sistem membuat gambar motivasi otomatis.

Tujuan:

- memunculkan promotor terbaik
- membangun motivasi
- diposting otomatis ke chat

Kategori:

- `Best Performance Harian`
- `Best Performance Mingguan`
- `Best Performance Bulanan`

Dasar penilaian:

- `Sell Out All Type`
- `Produk Fokus`

Waktu kirim:

- `22:00 WITA`

Tujuan chat:

- grup chat global per SPV
- semua orang dalam cakupan grup itu bisa melihat

Kalau seri:

- tampilkan `2 orang`

Konten gambar minimal:

- nama promotor
- kategori performa
- visual yang menarik

## Chat global

Ada chat global yang:

- menampung semua orang dalam kelompok SPV terkait
- menjadi tempat pengiriman informasi bersama
- menjadi tujuan auto-post best performance

## Prinsip kualitas sistem baru

Hal yang tidak boleh terulang:

- UI tidak seragam
- tampilan terlalu ramai
- penjelasan panjang ditaruh langsung di bawah menu
- query berat
- label dobel
- menu dobel
- data tidak satu arah
- sistem membingungkan saat diperbaiki

## Prinsip teknis yang harus diikuti

- satu istilah untuk satu arti
- satu sumber data untuk satu kebenaran
- query dashboard tidak boleh berat
- yang sering dibuka harus dibaca dari summary/agregat
- role dan hierarchy harus jelas
- data dan UI harus konsisten

## Belum diputuskan

Hal-hal berikut belum final dan tidak boleh diasumsikan sendiri:

- KPI final untuk trainer
- detail menu lengkap trainer selain fungsi utama yang sudah diputuskan
- detail formula ranking selain aturan umum yang sudah diputuskan
- detail visual final untuk poster best performance
