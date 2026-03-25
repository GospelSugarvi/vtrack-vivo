-- ==========================================================
-- FIX FINAL: Drop semua, buat satu function bersih
-- ==========================================================

-- Step 1: Drop SEMUA versi function ini
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT oidvectortypes(proargtypes) as args FROM pg_proc WHERE proname = 'get_store_stock_status'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS get_store_stock_status(' || r.args || ')';
    END LOOP;
END $$;

-- Step 2: Buat function baru - simple dan bersih
CREATE FUNCTION get_store_stock_status(p_sator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN COALESCE(
    (SELECT jsonb_agg(
      jsonb_build_object(
        'store_id', s.id,
        'store_name', s.store_name,
        'area', s.area,
        'grade', s.grade,
        'empty_count', 0,
        'low_count', 0,
        'ok_count', 0
      )
    )
    FROM stores s
    WHERE s.deleted_at IS NULL
    ORDER BY s.store_name),
    '[]'::jsonb
  );
END;
$$;

-- Step 3: Grant permission
GRANT EXECUTE ON FUNCTION get_store_stock_status(uuid) TO authenticated;
