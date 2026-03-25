-- ==========================================================
-- FIX ALL: Hapus semua referensi ideal_qty di stock_rules
-- ==========================================================

-- Lihat dulu function apa yang masih pake ideal_qty
SELECT proname 
FROM pg_proc 
WHERE prosrc LIKE '%stock_rules%' 
AND prosrc LIKE '%ideal_qty%';
