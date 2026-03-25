-- Add fullday shift type to shift_settings table

-- 1. Update CHECK constraint to include 'fullday'
ALTER TABLE shift_settings DROP CONSTRAINT IF EXISTS shift_settings_shift_type_check;
ALTER TABLE shift_settings ADD CONSTRAINT shift_settings_shift_type_check 
    CHECK (shift_type IN ('pagi', 'siang', 'fullday'));

-- 2. Insert default fullday settings
INSERT INTO shift_settings (shift_type, start_time, end_time, area, active) VALUES
('fullday', '08:00:00', '22:00:00', 'default', true)
ON CONFLICT (shift_type, area) DO UPDATE SET
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    active = EXCLUDED.active;

-- 3. Add fullday for Kupang area
INSERT INTO shift_settings (shift_type, start_time, end_time, area, active) VALUES
('fullday', '08:00:00', '22:00:00', 'Kupang', true)
ON CONFLICT (shift_type, area) DO UPDATE SET
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    active = EXCLUDED.active;

-- 4. Update get_shift_display function to handle fullday
CREATE OR REPLACE FUNCTION get_shift_display(p_shift_type TEXT, p_area TEXT DEFAULT 'default')
RETURNS TEXT AS $$
DECLARE
    shift_record RECORD;
    display_text TEXT;
BEGIN
    -- Get shift settings for area, fallback to default
    SELECT start_time, end_time INTO shift_record
    FROM shift_settings 
    WHERE shift_type = p_shift_type 
    AND area = p_area 
    AND active = true
    LIMIT 1;
    
    -- If not found for specific area, try default
    IF NOT FOUND THEN
        SELECT start_time, end_time INTO shift_record
        FROM shift_settings 
        WHERE shift_type = p_shift_type 
        AND area = 'default' 
        AND active = true
        LIMIT 1;
    END IF;
    
    -- Format display text
    IF FOUND THEN
        display_text := TO_CHAR(shift_record.start_time, 'HH24:MI') || '-' || TO_CHAR(shift_record.end_time, 'HH24:MI');
    ELSE
        -- Fallback to hardcoded if no settings found
        CASE p_shift_type
            WHEN 'pagi' THEN display_text := '08:00-16:00';
            WHEN 'siang' THEN display_text := '13:00-21:00';
            WHEN 'fullday' THEN display_text := '08:00-22:00';
            ELSE display_text := 'Unknown';
        END CASE;
    END IF;
    
    RETURN display_text;
END;
$$ LANGUAGE plpgsql;

-- 5. Verify
SELECT shift_type, start_time, end_time, area, active 
FROM shift_settings 
ORDER BY area, shift_type;
