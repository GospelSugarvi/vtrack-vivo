-- ==========================================================
-- GET ALL FUNCTION DEFINITIONS THAT USE stock_rules
-- ==========================================================

SELECT proname, prosrc
FROM pg_proc
WHERE proname IN (
  SELECT routine_name 
  FROM information_schema.routines 
  WHERE routine_schema = 'public'
)
AND prosrc LIKE '%stock_rules%'
ORDER BY proname;
