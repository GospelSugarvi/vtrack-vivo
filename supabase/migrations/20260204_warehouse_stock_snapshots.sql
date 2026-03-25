-- Create warehouse_stock_snapshots table for SATOR to record daily warehouse stock photos

CREATE TABLE IF NOT EXISTS warehouse_stock_snapshots (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    snapshot_date DATE NOT NULL,
    image_url TEXT NOT NULL,
    created_by UUID NOT NULL REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- One snapshot per date (prevent duplicate)
    UNIQUE(snapshot_date)
);

-- Add indexes
CREATE INDEX idx_warehouse_snapshots_date ON warehouse_stock_snapshots(snapshot_date DESC);
CREATE INDEX idx_warehouse_snapshots_created_by ON warehouse_stock_snapshots(created_by);

-- Add RLS policies
ALTER TABLE warehouse_stock_snapshots ENABLE ROW LEVEL SECURITY;

-- SATOR can view all snapshots
CREATE POLICY "SATOR can view all warehouse snapshots" ON warehouse_stock_snapshots
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role IN ('sator', 'spv', 'admin')
        )
    );

-- SATOR can create snapshots
CREATE POLICY "SATOR can create warehouse snapshots" ON warehouse_stock_snapshots
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role IN ('sator', 'spv', 'admin')
        )
        AND created_by = auth.uid()
    );

-- SATOR can update their own snapshots
CREATE POLICY "SATOR can update own warehouse snapshots" ON warehouse_stock_snapshots
    FOR UPDATE USING (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role IN ('sator', 'spv', 'admin')
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_warehouse_snapshots_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_warehouse_snapshots_updated_at
    BEFORE UPDATE ON warehouse_stock_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION update_warehouse_snapshots_updated_at();

-- Add function to check if snapshot exists for date
CREATE OR REPLACE FUNCTION check_warehouse_snapshot_exists(p_date DATE)
RETURNS TABLE(
    exists BOOLEAN,
    created_by_name TEXT,
    image_url TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        TRUE as exists,
        u.full_name as created_by_name,
        ws.image_url,
        ws.created_at
    FROM warehouse_stock_snapshots ws
    JOIN users u ON u.id = ws.created_by
    WHERE ws.snapshot_date = p_date
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT, NULL::TIMESTAMPTZ;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add function to get recent snapshots
CREATE OR REPLACE FUNCTION get_warehouse_snapshots(p_limit INT DEFAULT 30)
RETURNS TABLE(
    id UUID,
    snapshot_date DATE,
    image_url TEXT,
    created_by_name TEXT,
    created_by_avatar TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ws.id,
        ws.snapshot_date,
        ws.image_url,
        u.full_name as created_by_name,
        u.avatar_url as created_by_avatar,
        ws.notes,
        ws.created_at
    FROM warehouse_stock_snapshots ws
    JOIN users u ON u.id = ws.created_by
    ORDER BY ws.snapshot_date DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE warehouse_stock_snapshots IS 'Daily warehouse stock photos uploaded by SATOR';
COMMENT ON COLUMN warehouse_stock_snapshots.snapshot_date IS 'Date of the stock snapshot';
COMMENT ON COLUMN warehouse_stock_snapshots.image_url IS 'Cloudinary URL of stock photo';
COMMENT ON COLUMN warehouse_stock_snapshots.created_by IS 'SATOR who created the snapshot';

-- Insert sample data (optional, for testing)
-- INSERT INTO warehouse_stock_snapshots (snapshot_date, image_url, created_by, notes) VALUES
-- (CURRENT_DATE, 'https://via.placeholder.com/800x600', 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb', 'Stok lengkap hari ini');
