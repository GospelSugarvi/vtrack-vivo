-- ==========================================================
-- CARI DAN FIX FUNCTION YANG PAKAI ideal_qty
-- ==========================================================

-- Cari function yang punya sr.ideal_qty
SELECT proname
FROM pg_proc
WHERE prosrc LIKE '%sr.ideal_qty%';
