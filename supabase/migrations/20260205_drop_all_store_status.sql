-- ==========================================================
-- STEP 1: DROP SEMUA FUNCTION get_store_stock_status
-- ==========================================================

-- Hapus semua versi function ini
DO $$ 
DECLARE
    func_record RECORD;
BEGIN
    FOR func_record IN 
        SELECT proname, oidvectortypes(proargtypes) as args
        FROM pg_proc 
        WHERE proname = 'get_store_stock_status'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS get_store_stock_status(' || func_record.args || ')';
    END LOOP;
END $$;

-- Verifikasi sudah hilang
SELECT proname FROM pg_proc WHERE proname = 'get_store_stock_status';
