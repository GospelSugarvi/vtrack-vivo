# 📂 DOKUMENTASI PROYEK SATOR 2026

Berikut adalah panduan membaca dokumen perencanaan yang telah disusun.
File telah direname agar mudah dipahami konteksnya.

---

## 🟢 00. MASTER & KONSEP UTAMA
*   **`00_MASTER_CONCEPT_PLAN.md`**
    *   📖 **Baca ini dulu.**
    *   Isi: Rangkuman seluruh ide, visi misi, dan progress planning dari A-Z.

*   **`HANDOVER_05MAR2026_AGENT_CONTINUATION.md`**
    *   🆕 **Handover terbaru sesi agent (Promotor/SATOR feed sync).**
    *   Isi: akar masalah foto live feed, hardening upload, policy RLS update `sales_sell_out`, dan checklist audit parity.

*   **`HANDOVER_03MAR2026_AGENT.md`**
    *   Isi: status sesi 03 Mar 2026 (historical baseline), hasil analyzer bersih, dan perubahan penting modul SATOR Sell In (Stok Gudang).

*   **`HANDOVER_04MAR2026_ALLBRAND_UPDATE.md`**
    *   🆕 **Handover terbaru sesi agent (AllBrand).**
    *   Isi: update perbaikan AllBrand harian vs akumulasi, hardening SQL `jsonb_each`, hasil verifikasi DB, dan checklist lanjutan besok.

*   **`HANDOVER_05MAR2026_PHASE_EXECUTION_PLAN.md`**
    *   🧭 **Rencana eksekusi phase lintas agent (prioritas kerja terbaru).**
    *   Isi: breakdown Phase 1-4, status done/pending, DoD tiap phase, dependency teknis, dan checklist agar agent berikut tidak bingung.

*   **`HANDOVER_03MAR2026_DB_HARDENING.md`**
    *   🛡️ **Update hardening database + audit sinkronisasi FE-BE.**
    *   Isi: hasil audit live MCP Supabase, perbaikan RPC Stok Gudang, migration RLS tahap 1, guardrail audit SQL, plus artefak Phase 3 (migration + query verifikasi legacy cleanup).

*   **`HANDOVER_03MAR2026_SELLIN_FINALIZATION.md`**
    *   🧾 **Update besar flow Sell In (Draft -> Finalisasi).**
    *   Isi: refactor Order Manual/Rekomendasi, menu Finalisasi terpisah (Pending/Final + filter/sort), migration DB finalization, autosave draft, dan daftar pekerjaan lanjutan besok.

*   **`00_READ_ME_HANDOVER.md`**
    *   Isi: File ini (Daftar isi).

---

## 🔵 01. DATABASE & TEKNIS (Untuk Programmer)
*   **`01_DB_SCHEMA_DESIGN.md`**
    *   🔑 **Kunci Utama Sistem.**
    *   Isi: Desain tabel database (User, Produk, Target, Bonus). Ini yang akan di-copy ke Supabase SQL Editor.

*   **`01_DB_PERMISSION_RULES.md`**
    *   Isi: Aturan siapa boleh lihat apa (RLS).
    *   Contoh: "Promotor cuma boleh lihat data sendiri", "SATOR boleh lihat data timnya".

---

## 🟠 02. BUSINESS LOGIC (Otak Sistem)
*   **`02_LOGIC_BONUS_TARGETS.md`**
    *   💰 **"Kitab Suci" Uang.**
    *   Isi: Rumus hitung bonus, poin, denda, dan reward khusus untuk semua role (Promotor, SATOR, SPV). Semua angka duit ada di sini.

*   **`02_LOGIC_ADMIN_SYSTEM.md`**
    *   ⚙️ **Pusat Kontrol.**
    *   Isi: Fitur-fitur Admin untuk mengatur sistem (Enable/Disable aktivitas, Atur Target Mingguan, Manajemen User).

---

## 🟣 03. USER INTERFACE (Tampilan Aplikasi)
Ini adalah pasangan Logic di atas. Logic dieksekusi di background, UI adalah yang dilihat user di HP.

*   **`03_UI_PROMOTOR_ROLE.md`**
    *   📱 Tampilan untuk **Promotor**.
    *   Fitur: Input Jual, Absen, Cari Stok, Cek Bonus Pribadi.

*   **`03_UI_SATOR_ROLE.md`**
    *   📱 Tampilan untuk **SATOR**.
    *   Fitur: Monitoring Tim, Input Sell-In (Order), Cek Bonus Tim vs Target.
    *   *Pasangan Logic:* Menggunakan aturan poin di `02_LOGIC_BONUS_TARGETS.md`.

*   **`03_UI_SPV_MANAGER_ROLE.md`**
    *   📱 Tampilan untuk **SPV & Manager**.
    *   Fitur: Monitoring Area (SATOR), Strategi, Analisa Stok Agung.
    *   *Pasangan Logic:* Menggunakan aturan bonus SPV di `02_LOGIC_BONUS_TARGETS.md`.

---

## 🚀 PANDUAN MULAI (NEXT STEP)

1. **Buat Folder Project Baru.**
2. **Copy semua file** di atas ke folder tersebut.
3. **Setup Database** menggunakan script di `01_DB_SCHEMA_DESIGN.md`.
4. **Develop UI** mengikuti panduan di seri `03_UI_*`.
5. **Develop Logic** mengikuti panduan di seri `02_LOGIC_*`.

**Sistem Planning Selesai.** ✅
