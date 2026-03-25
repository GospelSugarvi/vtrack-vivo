CREATE TABLE IF NOT EXISTS schedule_review_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    month_year TEXT NOT NULL,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_name TEXT NOT NULL,
    author_role TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_schedule_review_comments_promotor_month
ON schedule_review_comments(promotor_id, month_year, created_at);

ALTER TABLE schedule_review_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Promotor can read own schedule comments" ON schedule_review_comments;
CREATE POLICY "Promotor can read own schedule comments" ON schedule_review_comments
FOR SELECT USING (
    promotor_id = auth.uid()
);

DROP POLICY IF EXISTS "Promotor can insert own schedule comments" ON schedule_review_comments;
CREATE POLICY "Promotor can insert own schedule comments" ON schedule_review_comments
FOR INSERT WITH CHECK (
    promotor_id = auth.uid() AND author_id = auth.uid()
);

DROP POLICY IF EXISTS "SATOR can read team schedule comments" ON schedule_review_comments;
CREATE POLICY "SATOR can read team schedule comments" ON schedule_review_comments
FOR SELECT USING (
    EXISTS (
        SELECT 1
        FROM hierarchy_sator_promotor hsp
        WHERE hsp.promotor_id = schedule_review_comments.promotor_id
        AND hsp.sator_id = auth.uid()
        AND hsp.active = true
    )
);

DROP POLICY IF EXISTS "SATOR can insert team schedule comments" ON schedule_review_comments;
CREATE POLICY "SATOR can insert team schedule comments" ON schedule_review_comments
FOR INSERT WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
        SELECT 1
        FROM hierarchy_sator_promotor hsp
        WHERE hsp.promotor_id = schedule_review_comments.promotor_id
        AND hsp.sator_id = auth.uid()
        AND hsp.active = true
    )
);

DROP POLICY IF EXISTS "SPV can read area schedule comments" ON schedule_review_comments;
CREATE POLICY "SPV can read area schedule comments" ON schedule_review_comments
FOR SELECT USING (
    EXISTS (
        SELECT 1
        FROM hierarchy_spv_sator hss
        JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = hss.sator_id
        WHERE hss.spv_id = auth.uid()
        AND hss.active = true
        AND hsp.active = true
        AND hsp.promotor_id = schedule_review_comments.promotor_id
    )
);

DROP POLICY IF EXISTS "SPV can insert area schedule comments" ON schedule_review_comments;
CREATE POLICY "SPV can insert area schedule comments" ON schedule_review_comments
FOR INSERT WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
        SELECT 1
        FROM hierarchy_spv_sator hss
        JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = hss.sator_id
        WHERE hss.spv_id = auth.uid()
        AND hss.active = true
        AND hsp.active = true
        AND hsp.promotor_id = schedule_review_comments.promotor_id
    )
);

DROP POLICY IF EXISTS "Admin can manage schedule review comments" ON schedule_review_comments;
CREATE POLICY "Admin can manage schedule review comments" ON schedule_review_comments
FOR ALL USING (
    EXISTS (
        SELECT 1
        FROM users u
        WHERE u.id = auth.uid()
        AND u.role = 'admin'
    )
);

CREATE OR REPLACE FUNCTION update_schedule_review_comments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_schedule_review_comments_updated_at ON schedule_review_comments;
CREATE TRIGGER trigger_update_schedule_review_comments_updated_at
    BEFORE UPDATE ON schedule_review_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_schedule_review_comments_updated_at();
