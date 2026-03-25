-- ==========================================================
-- JALANKAN INI DULU UNTUK CARI FUNCTION YANG BERMASALAH
-- ==========================================================

-- Cari semua function yang masih pake ideal_qty
SELECT 'Function: ' || proname as result
FROM pg_proc
WHERE prosrc LIKE '%ideal_qty%';
