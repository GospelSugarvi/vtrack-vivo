-- ==========================================================
-- CARI FUNCTION YANG PAKAI ideal_qty
-- ==========================================================

-- Cari semua function yang masih referensi ideal_qty
SELECT routine_name, routine_type
FROM information_schema.routines 
WHERE routine_schema = 'public'
AND routine_name IN (
  SELECT DISTINCT routine_name
  FROM information_schema.parameters p
  JOIN information_schema.routines r ON p.specific_schema = r.specific_schema AND p.specific_name = r.specific_name
  WHERE p.parameter_name = 'ideal_qty'
);

-- Atau cek lewat pg_proc
SELECT proname, prosrc
FROM pg_proc
WHERE proname LIKE '%stock%'
AND prosrc LIKE '%ideal_qty%';
