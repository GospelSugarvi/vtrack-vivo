# Legacy Root SQL Archive

Folder ini berisi file SQL lama dari root `supabase/` yang sudah tidak dipakai sebagai jalur migration aktif.

Isi arsip ini meliputi:

- script debug
- script audit manual
- one-off repair lama
- test query
- fix versi lama yang sudah digantikan migration atau phase SQL baru

Aturan pakai:

- jangan jadikan file di folder ini sebagai acuan utama implementasi baru
- gunakan hanya untuk referensi historis, audit, atau forensic
- untuk perubahan aktif, pakai `supabase/migrations/` atau phase SQL aktif di root `supabase/`
