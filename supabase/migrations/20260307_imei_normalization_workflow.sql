CREATE TABLE IF NOT EXISTS imei_normalization_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    normalization_id UUID NOT NULL REFERENCES imei_normalizations(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_role TEXT NOT NULL CHECK (author_role IN ('promotor', 'sator', 'spv', 'admin')),
    message TEXT NOT NULL,
    status_after TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_imei_normalization_comments_normalization
    ON imei_normalization_comments(normalization_id, created_at DESC);

ALTER TABLE imei_normalization_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Promotor can view own IMEI comments" ON imei_normalization_comments;
CREATE POLICY "Promotor can view own IMEI comments" ON imei_normalization_comments
    FOR SELECT USING (
        EXISTS (
            SELECT 1
            FROM imei_normalizations n
            WHERE n.id = imei_normalization_comments.normalization_id
              AND n.promotor_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Promotor can insert own IMEI comments" ON imei_normalization_comments;
CREATE POLICY "Promotor can insert own IMEI comments" ON imei_normalization_comments
    FOR INSERT WITH CHECK (
        auth.uid() = author_id
        AND author_role = 'promotor'
        AND EXISTS (
            SELECT 1
            FROM imei_normalizations n
            WHERE n.id = imei_normalization_comments.normalization_id
              AND n.promotor_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "SATOR can manage team IMEI comments" ON imei_normalization_comments;
CREATE POLICY "SATOR can manage team IMEI comments" ON imei_normalization_comments
    FOR ALL USING (
        EXISTS (
            SELECT 1
            FROM imei_normalizations n
            JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = n.promotor_id
            WHERE n.id = imei_normalization_comments.normalization_id
              AND hsp.sator_id = auth.uid()
              AND hsp.active = true
        )
    )
    WITH CHECK (
        auth.uid() = author_id
        AND author_role = 'sator'
        AND EXISTS (
            SELECT 1
            FROM imei_normalizations n
            JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = n.promotor_id
            WHERE n.id = imei_normalization_comments.normalization_id
              AND hsp.sator_id = auth.uid()
              AND hsp.active = true
        )
    );

DROP POLICY IF EXISTS "SPV can manage area IMEI comments" ON imei_normalization_comments;
CREATE POLICY "SPV can manage area IMEI comments" ON imei_normalization_comments
    FOR ALL USING (
        EXISTS (
            SELECT 1
            FROM imei_normalizations n
            JOIN users p ON p.id = n.promotor_id
            JOIN users u ON u.id = auth.uid()
            WHERE n.id = imei_normalization_comments.normalization_id
              AND u.role = 'spv'
              AND p.area = u.area
        )
    )
    WITH CHECK (
        auth.uid() = author_id
        AND author_role = 'spv'
        AND EXISTS (
            SELECT 1
            FROM imei_normalizations n
            JOIN users p ON p.id = n.promotor_id
            JOIN users u ON u.id = auth.uid()
            WHERE n.id = imei_normalization_comments.normalization_id
              AND u.role = 'spv'
              AND p.area = u.area
        )
    );

DROP POLICY IF EXISTS "Admin can manage all IMEI comments" ON imei_normalization_comments;
CREATE POLICY "Admin can manage all IMEI comments" ON imei_normalization_comments
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE id = auth.uid() AND role = 'admin'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users
            WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE OR REPLACE FUNCTION update_imei_normalization_comments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_imei_normalization_comments_updated_at ON imei_normalization_comments;
CREATE TRIGGER trigger_update_imei_normalization_comments_updated_at
    BEFORE UPDATE ON imei_normalization_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_imei_normalization_comments_updated_at();

UPDATE imei_normalizations
SET status = CASE
    WHEN status = 'pending' THEN 'reported'
    WHEN status = 'sent' THEN 'processing'
    WHEN status IN ('normalized', 'normal') THEN 'ready_to_scan'
    ELSE status
END
WHERE status IN ('pending', 'sent', 'normalized', 'normal');

ALTER TABLE imei_normalizations
DROP CONSTRAINT IF EXISTS imei_normalizations_status_check;

ALTER TABLE imei_normalizations
ADD CONSTRAINT imei_normalizations_status_check
CHECK (status IN (
    'reported',
    'processing',
    'ready_to_scan',
    'scanned',
    'pending',
    'sent',
    'normalized',
    'normal'
));
