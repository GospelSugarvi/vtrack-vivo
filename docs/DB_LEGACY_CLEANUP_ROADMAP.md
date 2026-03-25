# DB LEGACY CLEANUP ROADMAP
**Project:** VIVO Sales Management System  
**Date:** 10 March 2026  
**Status:** POST-FOUNDATION ROADMAP

---

## 1. PURPOSE

Dokumen ini menentukan object legacy atau compatibility layer yang tidak boleh dibiarkan menjadi bom waktu.

Tujuan:
- memastikan cleanup dilakukan terkontrol
- mencegah object lama terus dipakai tanpa sadar
- menentukan mana yang cukup diberi deprecation note dan mana yang harus diganti

---

## 2. CLEANUP PRINCIPLES

- jangan drop object lama sebelum read/write parity aman
- jangan rename fisik hanya demi rapi jika efek kompatibilitasnya besar
- prioritaskan block new misuse lebih dulu
- cleanup dilakukan setelah monitoring dan verifikasi

---

## 3. LEGACY / COMPATIBILITY OBJECTS TO TRACK

### 3.1 `sales_sell_out.estimated_bonus`

Status:
- masih dipakai compatibility

Risiko:
- developer baru bisa salah menganggap ini source utama bonus

Rencana:
- pertahankan sementara
- tambahkan deprecation note bila perlu
- read path bonus baru diarahkan ke `sales_bonus_events`

### 3.2 `dashboard_performance_metrics.estimated_bonus_total`

Status:
- masih dipakai dashboard lama

Risiko:
- jadi sumber bonus tunggal secara tidak sengaja

Rencana:
- pertahankan sementara
- pastikan parity check tetap tersedia
- migrasikan consumer bonus ke read model event-based

### 3.3 `sales_sell_in`

Status:
- compatibility feed/reporting

Risiko:
- ada fitur baru diam-diam insert/read dari sini sebagai source utama

Rencana:
- tandai sebagai compatibility layer
- arahkan fitur baru ke `sell_in_orders` dan `sell_in_order_items`

### 3.4 `stok`

Status:
- operational source valid, tapi naming hybrid

Risiko:
- kebingungan arsitektur karena blueprint menyebut `stock_items`

Rencana:
- jangan rename fisik sekarang
- gunakan naming konseptual di dokumen
- evaluasi rename hanya jika suatu saat biaya kompatibilitasnya kecil

### 3.5 `stock_movement_log`

Status:
- operational source valid, naming hybrid

Rencana:
- tetap dipakai
- diperlakukan sebagai `stock_movements` secara konseptual

### 3.6 JSON-heavy tables

Target evaluasi:
- `allbrand_reports`
- target detail yang masih terlalu berat di JSON

Risiko:
- query dan audit lebih sulit

Rencana:
- evaluasi kebutuhan pecah ke header-detail
- lakukan hanya bila manfaat jelas

---

## 4. CLEANUP PHASES

### Phase A: Deprecation Marking

Lakukan:
- beri comment/deprecation note
- update dokumentasi agar source of truth baru jelas

### Phase B: Read Path Migration

Lakukan:
- pindahkan consumer bonus ke read model baru
- pindahkan consumer sell-in ke order model finalized

### Phase C: Misuse Prevention

Lakukan:
- block write baru ke object yang benar-benar sudah obsolete
- tambahkan guardrail audit query

### Phase D: Optional Structural Cleanup

Lakukan hanya jika aman:
- rename fisik
- split table JSON-heavy
- hapus compatibility layer yang benar-benar sudah tidak dipakai

---

## 5. WHAT MUST NOT BE DONE CARELESSLY

- jangan drop `estimated_bonus_total` terlalu cepat
- jangan hapus `sales_sell_in` sebelum semua reporting aman
- jangan rename `stok`/`stock_movement_log` tanpa audit seluruh RPC, function, dan frontend
- jangan hitung ulang bonus historis dengan rule baru tanpa desain recalculation resmi

---

## 6. SUCCESS CRITERIA

Cleanup dianggap aman jika:
- tidak ada fitur aktif yang bergantung buta pada legacy object
- source of truth baru sudah dipakai consumer utama
- parity tetap tersedia atau tidak lagi dibutuhkan karena cutover selesai
- object legacy tidak lagi jadi pintu masuk fitur baru

---

## 7. RECOMMENDED NEXT EXECUTION

Urutan paling aman:

1. cutover read path bonus
2. audit read path sell-in
3. document deprecation comments
4. evaluate JSON-heavy tables
5. apply selective cleanup

