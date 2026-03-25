-- WITA Timezone Configuration for Supabase
-- UTC+8 (Waktu Indonesia Tengah)

-- 1. Set database timezone to WITA
ALTER DATABASE postgres SET timezone TO 'Asia/Makassar';

-- 2. Create helper function to get current WITA time
CREATE OR REPLACE FUNCTION now_wita()
RETURNS timestamptz AS $$
BEGIN
  RETURN now() AT TIME ZONE 'Asia/Makassar';
END;
$$ LANGUAGE plpgsql;

-- 3. Create function to get WITA date (for daily aggregations)
CREATE OR REPLACE FUNCTION today_wita()
RETURNS date AS $$
BEGIN
  RETURN (now() AT TIME ZONE 'Asia/Makassar')::date;
END;
$$ LANGUAGE plpgsql;

-- 4. Create function to convert any timestamp to WITA
CREATE OR REPLACE FUNCTION to_wita(ts timestamptz)
RETURNS timestamptz AS $$
BEGIN
  RETURN ts AT TIME ZONE 'Asia/Makassar';
END;
$$ LANGUAGE plpgsql;

-- 5. Set session timezone for all new connections
-- This ensures all timestamp operations default to WITA
ALTER ROLE postgres SET timezone = 'Asia/Makassar';

-- NOTE: After running this migration:
-- - All new timestamps will be stored in WITA context
-- - Use now_wita() instead of now() for explicit WITA time
-- - Use today_wita() for date-based queries
-- - Existing data remains unchanged (stored as UTC)
