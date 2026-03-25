-- Verify legacy safeguard for public.stok_gudang_harian

-- 1) Deprecated comment
SELECT
  c.relname AS table_name,
  d.description AS table_comment
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_description d ON d.objoid = c.oid AND d.objsubid = 0
WHERE n.nspname = 'public'
  AND c.relname = 'stok_gudang_harian';

-- 2) Trigger exists and enabled
SELECT
  tg.tgname AS trigger_name,
  pg_get_triggerdef(tg.oid) AS trigger_def,
  tg.tgenabled AS trigger_enabled
FROM pg_trigger tg
JOIN pg_class c ON c.oid = tg.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'stok_gudang_harian'
  AND tg.tgname = 'trg_block_legacy_stok_gudang_harian_writes'
  AND NOT tg.tgisinternal;

-- 3) Role privileges matrix (anon/authenticated)
SELECT
  r.rolname AS role_name,
  has_table_privilege(r.rolname, 'public.stok_gudang_harian', 'SELECT') AS can_select,
  has_table_privilege(r.rolname, 'public.stok_gudang_harian', 'INSERT') AS can_insert,
  has_table_privilege(r.rolname, 'public.stok_gudang_harian', 'UPDATE') AS can_update,
  has_table_privilege(r.rolname, 'public.stok_gudang_harian', 'DELETE') AS can_delete
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated')
ORDER BY r.rolname;
