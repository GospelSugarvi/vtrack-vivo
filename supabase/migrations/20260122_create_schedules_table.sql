-- Create schedules table for promotor work schedules
CREATE TABLE schedules (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    schedule_date DATE NOT NULL,
    shift_type TEXT NOT NULL CHECK (shift_type IN ('pagi', 'siang', 'libur')),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'rejected')),
    sator_comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure one schedule per promotor per date
    UNIQUE(promotor_id, schedule_date)
);

-- Add indexes for better performance
CREATE INDEX idx_schedules_promotor_date ON schedules(promotor_id, schedule_date);
CREATE INDEX idx_schedules_status ON schedules(status);
CREATE INDEX idx_schedules_date_range ON schedules(schedule_date);

-- Add RLS policies
ALTER TABLE schedules ENABLE ROW LEVEL SECURITY;

-- Promotor can only see and manage their own schedules
CREATE POLICY "Promotor can manage own schedules" ON schedules
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- SATOR can view and approve schedules of their team promotors
CREATE POLICY "SATOR can manage team schedules" ON schedules
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = schedules.promotor_id
            AND hsp.active = true
        )
    );

-- SPV can view schedules in their area
CREATE POLICY "SPV can view area schedules" ON schedules
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = schedules.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

-- Manager can view all schedules
CREATE POLICY "Manager can view all schedules" ON schedules
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'manager'
        )
    );

-- Admin can manage all schedules
CREATE POLICY "Admin can manage all schedules" ON schedules
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_schedules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_schedules_updated_at
    BEFORE UPDATE ON schedules
    FOR EACH ROW
    EXECUTE FUNCTION update_schedules_updated_at();

-- Add comments
COMMENT ON TABLE schedules IS 'Work schedules for promotors with shift types and approval status';
COMMENT ON COLUMN schedules.shift_type IS 'Type of shift: pagi (08:00-16:00), siang (13:00-21:00), libur (off)';
COMMENT ON COLUMN schedules.status IS 'Schedule status: draft, submitted (waiting approval), approved, rejected';