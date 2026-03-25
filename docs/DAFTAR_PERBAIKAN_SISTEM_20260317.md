# Daftar Perbaikan & Pengembangan Sistem
**Tanggal Update:** Selasa, 17 Maret 2026
**Status Proyek:** Fase Perbaikan & Optimalisasi UI/UX/Fitur

Dokumen ini digunakan untuk melacak progres perbaikan sistem. Gunakan tanda `[x]` untuk menandai fitur yang sudah selesai dikerjakan dan direview.

---

## I. UI/UX & Visual Enhancement
*   [x] **1. Optimalisasi Kontras Font:** Memperbaiki warna tulisan pada Card agar lebih kontras dan informatif. Diterapkan untuk SEMUA role (Promotor, Sator, SPV, Admin). (SELESAI 17/03/2026)
*   [ ] **2. Status Warna Otomatis:** Perubahan warna indikator Workplace dari MERAH ke HIJAU secara otomatis setelah laporan diisi.
*   [ ] **3. Redesain Notifikasi:** Mengubah notifikasi "Berhasil/Refresh" dari snackbar bawah menjadi tampilan pop-up di tengah layar dengan ukuran teks yang lebih proporsional.
*   [x] **4. Interaktivitas Leaderboard:** (SELESAI 17/03/2026)
    *   [x] Penambahan fitur *Pull-to-Refresh*.
    *   [x] Menampilkan foto profil user pada podium juara (Desain Flat/Clean).
*   [x] **5. Footer Target Harian:** Penambahan baris total (Summary) di bagian bawah daftar target untuk menampilkan akumulasi pencapaian. (SELESAI 17/03/2026)
    *   [x] Diterapkan pada Detail Target Promotor.
    *   [x] Diterapkan pada Dashboard Harian Sator (Card & Sheet).

## II. Fitur Sosial & Live Feed
*   [ ] **6. Layout Horizontal Feed:** Mengubah tampilan Live Feed menjadi gaya horizontal (Instagram-style).
*   [ ] **7. Fitur Interaksi Feed:** 
    *   [ ] Penambahan komentar dan reaksi emoji.
    *   [ ] Implementasi **AI Congratulation** (Setting AI dikelola melalui halaman Admin).

## III. Sistem Komunikasi (Messaging)
*   [ ] **8. Modernisasi Chat (WhatsApp Style):**
    *   [ ] Update model data agar mendukung komunikasi Real-time.
    *   [ ] Implementasi Firebase Cloud Messaging (FCM) untuk Push Notification.
    *   [ ] Penyesuaian UI Chat agar identik dengan standar kenyamanan WhatsApp.
*   [ ] **9. Integrasi Data Laporan ke Chat:** Sator dan SPV dapat melihat data laporan toko/promotor secara langsung di dalam ruang chat untuk mempermudah kontrol dan motivasi.

## IV. Manajemen Konsumen & VAST System
*   [ ] **10. Fitur Pengingat VAST:**
    *   [ ] Deteksi data duplikat.
    *   [ ] Early Warning untuk konsumen yang masa kreditnya hampir berakhir.
    *   [ ] Dashboard jadwal cicilan bulanan untuk pengingat follow-up Promotor.
*   [ ] **11. Modul "Konsumen Saya":**
    *   [ ] Database list konsumen mandiri bagi setiap Promotor.
    *   [ ] Sinkronisasi otomatis antara input penjualan dengan database VAST.

## V. Fungsionalitas & Kontrol Sistem
*   [ ] **12. Pelaporan Terjadwal:** Sistem laporan rutin jam 14:00 dan 18:00 (Sator dapat mengirimkan instruksi laporan dari Control Room).
*   [x] **13. Transparansi Penjualan Nasional:** (DALAM PROSES) Menghapus filter area agar data nasional terlihat oleh semua role.
*   [ ] **14. Optimalisasi Fitur Search:** Pencarian berdasarkan Nama Konsumen dan Nama Toko yang menampilkan profil data lengkap.
*   [ ] **15. Simplifikasi Alur Kerja:** Penyederhanaan (simplifikasi) proses Normalisasi IMEI dan sistem Order dengan menghapus langkah-langkah yang tidak perlu.

---

## Log Review & Update
| Tanggal | Fitur | Status | Catatan |
| :--- | :--- | :--- | :--- |
| 17/03/2026 | Semua | *Planning* | Dokumen awal dibuat. |
| 17/03/2026 | Poin 1 (Kontras Font) | **Selesai** | Peningkatan kontras global, penebalan judul, dan pembesaran font size (9->11, dsb) di seluruh sistem (Admin, Sator, SPV, Promotor). |
| 17/03/2026 | Poin 4 (Leaderboard) | **Selesai** | Implementasi Pull-to-Refresh dan foto profil flat pada podium. |
| 17/03/2026 | Poin 5 (Footer Target) | **Selesai** | Penambahan ringkasan totalan tim di Dashboard Sator dan Detail Target Promotor. |
