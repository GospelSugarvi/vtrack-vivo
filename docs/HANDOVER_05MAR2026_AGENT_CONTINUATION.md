# HANDOVER 05 MAR 2026 - AGENT CONTINUATION (PROMOTOR/SATOR FEED)

## Ringkasan Kondisi Terakhir
- Fokus issue hari ini: `SATOR > Laporan > Live Feed` tidak sinkron dengan data Promotor, terutama foto jualan.
- Akar masalah utama yang terbukti:
  1. Upload Cloudinary sempat timeout (sudah di-hardening timeout + retry).
  2. `sales_sell_out.image_proof_url` tidak ter-update karena policy UPDATE belum ada (RLS).
  3. SATOR feed sempat bergantung payload RPC yang tidak selalu bawa field foto lengkap.

## Status Fix yang Sudah Dikerjakan

### A. App (Flutter)
1. `lib/features/sator/presentation/tabs/sator_sales_tab.dart`
- Live feed dirender pakai data merge:
  - base dari `sales_sell_out` (source of truth image)
  - metadata dari RPC (reaction/comment) di-merge by `sale_id`.
- Tambah sync image URL dari tabel ke `_liveFeed`.
- Hapus card area/SPV biru (`area_header` tidak dirender).
- Realtime refresh dibuat debounce (`_scheduleRealtimeReload`) untuk kurangi spam reload dan jank.

2. `lib/features/promotor/presentation/pages/leaderboard_page.dart`
- `SalesCard` fallback image baca:
  - `image_url`
  - `image_proof_url`
- Jika perlu, card resolve ulang image by `sale_id` ke tabel `sales_sell_out`.

3. `lib/features/promotor/presentation/pages/sell_out_page.dart`
- Upload Cloudinary timeout dinaikkan (60s).
- Retry background upload sampai 3x.
- Kompres gambar tidak dipakai jika hasil kompres justru lebih besar.
- Debug log sementara dibersihkan kembali setelah investigasi.

### B. DB (Supabase)
1. File migration dibuat:
- `supabase/migrations/20260305_fix_sales_sellout_update_policy.sql`

Isi penting:
- enable RLS (idempotent)
- create policy `Sales update own` pada `sales_sell_out` untuk `UPDATE` oleh promotor owner row.

2. Bukti akar masalah sebelumnya (sudah tervalidasi):
- log app menunjukkan `db update affected_rows=0` sebelum policy update diterapkan.

## Query Audit yang Sudah Disiapkan
- `supabase/queries/20260305_promotor_sator_parity_audit.sql`

Tujuan:
- cek parity data table vs RPC untuk:
  - live feed row harian
  - live feed with image
  - leaderboard monthly units/revenue/bonus
- helper detail mismatch `sale_id` yang hilang dari RPC feed.

## Langkah Lanjutan Agent Besok (URUT)
1. Jalankan audit parity SQL
- file: `supabase/queries/20260305_promotor_sator_parity_audit.sql`
- ganti `v_sator_id` dulu.
- eksekusi untuk minimal 2 tanggal (hari ini + 1 hari sebelumnya).

2. Jika ada FAIL pada parity live feed
- prioritas cek function DB `get_live_feed` (filter area/date dan payload image).
- pastikan row tim SATOR benar-benar included.

3. QA di device (manual)
- Upload 2 transaksi baru dengan foto.
- Verifikasi di:
  - Promotor Live Feed
  - SATOR Live Feed
- pastikan foto tampil tanpa pindah tanggal/tab.

4. Jika performa masih jank
- profil rebuild di `SatorSalesTab` (DevTools Flutter Performance).
- fokus pada `ListView` feed dan refresh trigger.

## Catatan Penting
- Jangan rollback perubahan UI storytelling yang sudah disetujui user.
- Jangan hapus route/menu yang sudah dipakai (`Reports Sellout Tim`).
- Jangan ubah hard policy lain tanpa audit dampak RLS.

## Checklist Verifikasi Cepat (Done Criteria)
- [ ] Upload foto jualan sukses dan tersimpan di `sales_sell_out.image_proof_url`
- [ ] Foto tampil di Promotor Live Feed
- [ ] Foto tampil di SATOR Live Feed
- [ ] Audit parity SQL dominan `PASS`
- [ ] Tidak ada overflow/error fatal di tab Laporan

