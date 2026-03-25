-- ==========================================================
-- CARI FUNCTION DENGAN ideal_qty LALU FIX
-- ==========================================================

-- Step 1: Cari function yang masih pake ideal_qty
SELECT proname as function_name
FROM pg_proc
WHERE prosrc LIKE '%ideal_qty%';

-- Step 2: Setelah ketemu, drop function tersebut
-- DROP FUNCTION IF EXISTS function_name(args);
