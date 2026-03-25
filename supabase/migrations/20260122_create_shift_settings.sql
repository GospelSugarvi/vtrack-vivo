-- Create shift_settings table for admin to control work hours
CREATE TABLE shift_settings (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    shift_type TEXT NOT NULL CHECK (shift_type IN ('pagi', 'siang')),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    area TEXT NOT NULL DEFAULT 'default',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure one setting per shift type per area
    UNIQUE(shift_type, area)
);

-- Insert default shift settings
INSERT INTO shift_settings (shift_type, start_time, end_time, area, active) VALUES
('pagi', '08:00:00', '16:00:00', 'default', true),
('siang', '13:00:00', '21:00:00', 'default', true);

-- Add area-specific settings (example for Kupang)
INSERT INTO shift_settings (shift_type, start_time, end_time, area, active) VALUES
('pagi', '08:00:00', '16:00:00', 'Kupang', true),
('siang', '13:00:00', '21:00:00', 'Kupang', true);

-- Add indexes for better performance
CREATE INDEX idx_shift_settings_area ON shift_settings(area);
CREATE INDEX idx_shift_settings_active ON shift_settings(active);

-- Add RLS policies
ALTER TABLE shift_settings ENABLE ROW LEVEL SECURITY;

-- Everyone can read shift settings (needed for schedule display)
CREATE POLICY "Everyone can read shift settings" ON shift_settings
    FOR SELECT USING (active = true);

-- Only admin can manage shift settings
CREATE POLICY "Admin can manage shift settings" ON shift_settings
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_shift_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_shift_settings_updated_at
    BEFORE UPDATE ON shift_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_shift_settings_updated_at();

-- Add function to get shift time display
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
            ELSE display_text := 'Unknown';
        END CASE;
    END IF;
    
    RETURN display_text;
END;
$$ LANGUAGE plpgsql;

-- Add comments
COMMENT ON TABLE shift_settings IS 'Admin-configurable work shift hours per area';
COMMENT ON COLUMN shift_settings.shift_type IS 'Type of shift: pagi or siang';
COMMENT ON COLUMN shift_settings.area IS 'Area name, use "default" for global settings';
COMMENT ON FUNCTION get_shift_display IS 'Get formatted shift time display (HH:MM-HH:MM)';