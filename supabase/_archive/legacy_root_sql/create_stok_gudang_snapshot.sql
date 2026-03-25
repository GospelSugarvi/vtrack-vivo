-- Create table for warehouse stock photo snapshots
-- Different from stok_gudang_harian which is for detailed product inventory
-- This is for overall warehouse photo documentation

CREATE TABLE IF NOT EXISTS stok_gudang_snapshot (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tanggal DATE NOT NULL UNIQUE, -- One snapshot per day
    foto_url TEXT NOT NULL, -- Cloudinary URL
    catatan TEXT, -- Optional notes
    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes
CREATE INDEX idx_stok_gudang_snapshot_tanggal ON stok_gudang_snapshot(tanggal DESC);
CREATE INDEX idx_stok_gudang_snapshot_created_by ON stok_gudang_snapshot(created_by);

-- Add RLS policies
ALTER TABLE stok_gudang_snapshot ENABLE ROW LEVEL SECURITY;

-- SATOR/SPV/Admin can view all snapshots
CREATE POLICY "SATOR can view warehouse snapshots" ON stok_gudang_snapshot
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role IN ('sator', 'spv', 'admin')
        )
    );

-- SATOR/SPV/Admin can create snapshots
CREATE POLICY "SATOR can create warehouse snapshots" ON stok_gudang_snapshot
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role IN ('sator', 'spv', 'admin')
        )
        AND created_by = auth.uid()
    );

-- SATOR can update their own snapshots (same day only)
CREATE POLICY "SATOR can update own snapshots" ON stok_gudang_snapshot
    FOR UPDATE USING (
        created_by = auth.uid()
        AND tanggal = CURRENT_DATE -- Only today's snapshot
        AND EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role IN ('sator', 'spv', 'admin')
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_stok_gudang_snapshot_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_stok_gudang_snapshot_updated_at
    BEFORE UPDATE ON stok_gudang_snapshot
    FOR EACH ROW
    EXECUTE FUNCTION update_stok_gudang_snapshot_updated_at();

-- Function to check if snapshot exists for a date
CREATE OR REPLACE FUNCTION check_snapshot_exists(p_tanggal DATE)
RETURNS TABLE(
    exists BOOLEAN,
    created_by_name TEXT,
    created_by_avatar TEXT,
    foto_url TEXT,
    catatan TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        TRUE as exists,
        u.full_name as created_by_name,
        u.avatar_url as created_by_avatar,
        s.foto_url,
        s.catatan,
        s.created_at
    FROM stok_gudang_snapshot s
    JOIN users u ON u.id = s.created_by
    WHERE s.tanggal = p_tanggal
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TEXT, NULL::TIMESTAMPTZ;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get recent snapshots with creator info
CREATE OR REPLACE FUNCTION get_stok_gudang_snapshots(p_limit INT DEFAULT 30)
RETURNS TABLE(
    id UUID,
    tanggal DATE,
    foto_url TEXT,
    catatan TEXT,
    created_by_name TEXT,
    created_by_avatar TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.id,
        s.tanggal,
        s.foto_url,
        s.catatan,
        u.full_name as created_by_name,
        u.avatar_url as created_by_avatar,
        s.created_at
    FROM stok_gudang_snapshot s
    JOIN users u ON u.id = s.created_by
    ORDER BY s.tanggal DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE stok_gudang_snapshot IS 'Daily warehouse stock photo snapshots uploaded by SATOR';
COMMENT ON COLUMN stok_gudang_snapshot.tanggal IS 'Date of the stock snapshot (one per day)';
COMMENT ON COLUMN stok_gudang_snapshot.foto_url IS 'Cloudinary URL of warehouse stock photo';
COMMENT ON COLUMN stok_gudang_snapshot.catatan IS 'Optional notes about the stock condition';
COMMENT ON COLUMN stok_gudang_snapshot.created_by IS 'SATOR who created the snapshot';

-- Verify
SELECT 'Table stok_gudang_snapshot created successfully' as status;
