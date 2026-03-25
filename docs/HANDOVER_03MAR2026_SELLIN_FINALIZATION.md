# HANDOVER SELL IN FINALIZATION - 03 Mar 2026 (Malam)

## Ringkasan
Fokus sesi ini adalah merapikan flow Sell In agar profesional, mudah dipakai, dan valid untuk hitung target bulanan.

Keputusan arsitektur yang dipakai:
1. Order dibuat sebagai `pending` (draft).
2. Finalisasi dipisah ke menu khusus.
3. Hanya order `finalized` yang dihitung sebagai realisasi Sell In.

---

## 1) Perubahan UI/UX yang Sudah Selesai

### A. Stok Gudang dibuat compact
File:
- `lib/features/sator/presentation/pages/sell_in/stok_gudang_page.dart`

Update:
1. List digrup per produk (expand/collapse).
2. Toggle `Tersedia saja` default aktif.
3. Ringkasan cepat: jumlah produk, varian, total unit.
4. Search diperluas (produk/varian/warna).

### B. Stok Toko dibuat compact
File:
- `lib/features/promotor/presentation/pages/stok_toko_page.dart`

Update:
1. Search + filter cepat.
2. Grup per produk (lebih pendek, minim scroll).
3. Hapus duplikasi modal rekomendasi + hapus fitur salin rekomendasi dari halaman ini.
4. Rekomendasi diarahkan ke halaman rekomendasi utama (single source of truth).

### C. Halaman Rekomendasi dibuat lebih simple
File:
- `lib/features/sator/presentation/pages/sell_in/rekomendasi_page.dart`

Update:
1. Hapus interaksi swipe remove/pulihkan yang membingungkan.
2. Tambah search + filter cepat.
3. Kontrol qty ringkas (`- qty +`).
4. Tambah aksi `Simpan Draft` (sebelumnya finalisasi langsung).

### D. Fitur baru: Order Manual terpisah
File:
- `lib/features/sator/presentation/pages/sell_in/order_manual_page.dart`

Update:
1. Flow terpisah dari rekomendasi (full manual).
2. Input qty cepat (tap angka -> input keyboard).
3. Step indicator 3 tahap: Pilih Toko -> Input Qty -> Preview.
4. Preview + download gambar order.
5. Header gambar dibuat netral: `DAFTAR ORDER VIVO`.
6. Autosave draft per user + per toko (shared_preferences).

### E. Menu baru: Finalisasi Sell In
File:
- `lib/features/sator/presentation/pages/sell_in/finalisasi_sellin_page.dart`

Update:
1. Tab `Pending`: finalisasi order satu per satu.
2. Tab `Final`: tracking order final.
3. Filter tanggal (`from-to`), filter toko, mode per tanggal/per bulan, sorting.
4. Rekap total unit dan total nilai pada hasil final.
5. Perbaikan responsif untuk layar kecil (fix RenderFlex overflow).

### F. Routing/menu yang diupdate
File:
- `lib/core/router/app_router.dart`
- `lib/features/sator/presentation/pages/sell_in/sell_in_dashboard_page.dart`
- `lib/features/sator/presentation/tabs/sator_stock_tab.dart`
- `lib/features/sator/presentation/pages/sell_in/list_toko_page.dart`

Update:
1. Route `Order Manual` ditambahkan.
2. Route `Finalisasi Sell In` ditambahkan.
3. Quick action/menu card di dashboard diupdate agar flow draft -> finalisasi terlihat jelas.
4. Tombol order dari list toko diarahkan ke flow manual.

---

## 2) Perubahan Database yang Sudah Disiapkan

### A. Finalization MVP
File migration:
- `supabase/migrations/20260303_sellin_finalization_mvp.sql`

Cakupan:
1. Tabel `sell_in_orders` + `sell_in_order_items`.
2. RPC finalisasi langsung `finalize_sell_in_order(...)`.
3. `get_sator_sellin_summary(...)` dan `get_pending_orders(...)` disesuaikan.

### B. Pending -> Finalisasi terpisah (flow final yang dipakai)
File migration:
- `supabase/migrations/20260303_sellin_pending_finalization_flow.sql`

Cakupan:
1. `save_sell_in_order_draft(...)` untuk simpan draft pending.
2. `get_sell_in_order_detail(...)` untuk detail order.
3. `finalize_sell_in_order_by_id(...)` untuk finalisasi terkontrol.
4. `get_pending_orders(...)` diperkaya untuk kebutuhan UI finalisasi.

Catatan:
- Migration `20260303_sellin_pending_finalization_flow.sql` adalah kunci flow terbaru.

---

## 3) Status Validasi

1. `flutter analyze` pada file-file yang diubah: PASS (no issues).
2. Fix overflow di halaman finalisasi sudah diterapkan.
3. Ringkas: flow sekarang adalah
   - Buat order -> Simpan Draft
   - Masuk menu Finalisasi -> Finalisasi per order
   - Data finalized tercatat dan siap dihitung ke target.

---

## 4) Checklist Besok (Next Session)

1. Verifikasi DB live untuk flow draft->finalized:
   - draft masuk `sell_in_orders` status pending
   - finalize by id ubah status jadi finalized
   - detail item konsisten
   - feed `sales_sell_in` terisi
2. Sinkronkan halaman `SellInAchievementPage` agar 100% baca dari sumber finalized flow baru (bukan jalur lama).
3. Tambah guardrail query khusus Sell In finalization (monitor pending/finalized mismatch).
4. Uji end-to-end user scenario di device kecil untuk memastikan tidak ada overflow sisa.

---

## 5) Catatan Operasional

1. Untuk perhitungan target bulanan, referensi utama harus `finalized` saja.
2. Draft (`pending`) tidak boleh mempengaruhi KPI.
3. Bila diperlukan audit, gunakan `sell_in_orders` sebagai header transaksi resmi.
