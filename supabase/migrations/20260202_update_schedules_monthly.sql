-- Update schedules table for monthly submission system
-- Add columns for monthly grouping and rejection tracking

-- Add month_year column for grouping schedules by month
ALTER TABLE schedules 
ADD COLUMN IF NOT EXISTS month_year TEXT;

-- Add rejection_reason column (separate from sator_comment)
ALTER TABLE schedules 
ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Populate month_year for existing records
UPDATE schedules 
SET month_year = TO_CHAR(schedule_date, 'YYYY-MM')
WHERE month_year IS NULL;

-- Make month_year NOT NULL after populating
ALTER TABLE schedules 
ALTER COLUMN month_year SET NOT NULL;

-- Add index for month_year queries
CREATE INDEX IF NOT EXISTS idx_schedules_month_year ON schedules(promotor_id, month_year);

-- Drop old RLS policy for promotor that prevents editing approved schedules
DROP POLICY IF EXISTS "Promotor can manage own schedules" ON schedules;

-- Create new policy that allows promotor to edit their own schedules (including approved ones)
CREATE POLICY "Promotor can manage own schedules" ON schedules
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- Update SATOR policy to use store assignments instead of hierarchy
DROP POLICY IF EXISTS "SATOR can manage team schedules" ON schedules;

CREATE POLICY "SATOR can manage team schedules" ON schedules
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND EXISTS (
                -- SATOR can see schedules of promotors who work in stores assigned to this SATOR
                SELECT 1 
                FROM assignments_sator_store ass
                JOIN assignments_promotor_store aps ON aps.store_id = ass.store_id
                WHERE ass.sator_id = u.id
                AND ass.active = true
                AND aps.promotor_id = schedules.promotor_id
                AND aps.active = true
            )
        )
    );

-- Create function to copy previous month's schedule
CREATE OR REPLACE FUNCTION copy_previous_month_schedule(
    p_promotor_id UUID,
    p_target_month TEXT -- Format: 'YYYY-MM'
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    copied_count INTEGER
) AS $$
DECLARE
    v_previous_month TEXT;
    v_copied_count INTEGER := 0;
    v_target_date DATE;
    v_days_in_month INTEGER;
    v_schedule_record RECORD;
BEGIN
    -- Calculate previous month
    v_target_date := (p_target_month || '-01')::DATE;
    v_previous_month := TO_CHAR(v_target_date - INTERVAL '1 month', 'YYYY-MM');
    v_days_in_month := EXTRACT(DAY FROM (DATE_TRUNC('month', v_target_date) + INTERVAL '1 month' - INTERVAL '1 day'));
    
    -- Check if target month already has schedules
    IF EXISTS (
        SELECT 1 FROM schedules 
        WHERE promotor_id = p_promotor_id 
        AND month_year = p_target_month
    ) THEN
        RETURN QUERY SELECT false, 'Target month already has schedules. Delete them first.', 0;
        RETURN;
    END IF;
    
    -- Check if previous month has schedules
    IF NOT EXISTS (
        SELECT 1 FROM schedules 
        WHERE promotor_id = p_promotor_id 
        AND month_year = v_previous_month
    ) THEN
        RETURN QUERY SELECT false, 'No schedules found in previous month to copy.', 0;
        RETURN;
    END IF;
    
    -- Copy schedules from previous month
    FOR v_schedule_record IN 
        SELECT shift_type, EXTRACT(DAY FROM schedule_date)::INTEGER as day_num
        FROM schedules
        WHERE promotor_id = p_promotor_id
        AND month_year = v_previous_month
        ORDER BY schedule_date
    LOOP
        -- Only copy if the day exists in target month
        IF v_schedule_record.day_num <= v_days_in_month THEN
            INSERT INTO schedules (
                promotor_id,
                schedule_date,
                shift_type,
                status,
                month_year
            ) VALUES (
                p_promotor_id,
                (p_target_month || '-' || LPAD(v_schedule_record.day_num::TEXT, 2, '0'))::DATE,
                v_schedule_record.shift_type,
                'draft',
                p_target_month
            );
            v_copied_count := v_copied_count + 1;
        END IF;
    END LOOP;
    
    RETURN QUERY SELECT true, 'Successfully copied ' || v_copied_count || ' schedules from ' || v_previous_month, v_copied_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to get schedule status summary for SATOR
CREATE OR REPLACE FUNCTION get_sator_schedule_summary(
    p_sator_id UUID,
    p_month_year TEXT -- Format: 'YYYY-MM'
)
RETURNS TABLE (
    promotor_id UUID,
    promotor_name TEXT,
    store_name TEXT,
    status TEXT,
    total_days INTEGER,
    submitted_at TIMESTAMPTZ,
    last_updated TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (u.id)
        u.id as promotor_id,
        u.full_name as promotor_name,
        s.name as store_name,
        COALESCE(
            (
                SELECT sch.status 
                FROM schedules sch 
                WHERE sch.promotor_id = u.id 
                AND sch.month_year = p_month_year 
                LIMIT 1
            ),
            'belum_kirim'
        ) as status,
        COALESCE(
            (
                SELECT COUNT(*)::INTEGER 
                FROM schedules sch 
                WHERE sch.promotor_id = u.id 
                AND sch.month_year = p_month_year
            ),
            0
        ) as total_days,
        (
            SELECT MIN(sch.updated_at) 
            FROM schedules sch 
            WHERE sch.promotor_id = u.id 
            AND sch.month_year = p_month_year 
            AND sch.status = 'submitted'
        ) as submitted_at,
        (
            SELECT MAX(sch.updated_at) 
            FROM schedules sch 
            WHERE sch.promotor_id = u.id 
            AND sch.month_year = p_month_year
        ) as last_updated
    FROM users u
    JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
    JOIN stores s ON s.id = aps.store_id
    JOIN assignments_sator_store ass ON ass.store_id = s.id
    WHERE u.role = 'promotor'
    AND ass.sator_id = p_sator_id
    AND ass.active = true
    AND aps.active = true
    ORDER BY u.id, s.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to submit monthly schedule
CREATE OR REPLACE FUNCTION submit_monthly_schedule(
    p_promotor_id UUID,
    p_month_year TEXT
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_schedule_count INTEGER;
BEGIN
    -- Check if schedules exist for this month
    SELECT COUNT(*) INTO v_schedule_count
    FROM schedules
    WHERE promotor_id = p_promotor_id
    AND month_year = p_month_year;
    
    IF v_schedule_count = 0 THEN
        RETURN QUERY SELECT false, 'No schedules found for this month.';
        RETURN;
    END IF;
    
    -- Update all schedules for this month to submitted
    UPDATE schedules
    SET status = 'submitted',
        updated_at = NOW()
    WHERE promotor_id = p_promotor_id
    AND month_year = p_month_year
    AND status = 'draft';
    
    RETURN QUERY SELECT true, 'Schedule submitted successfully for approval.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to approve/reject monthly schedule
CREATE OR REPLACE FUNCTION review_monthly_schedule(
    p_sator_id UUID,
    p_promotor_id UUID,
    p_month_year TEXT,
    p_action TEXT, -- 'approve' or 'reject'
    p_rejection_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_new_status TEXT;
BEGIN
    -- Verify SATOR has access to this promotor
    IF NOT EXISTS (
        SELECT 1 
        FROM assignments_sator_store ass
        JOIN assignments_promotor_store aps ON aps.store_id = ass.store_id
        WHERE ass.sator_id = p_sator_id
        AND ass.active = true
        AND aps.promotor_id = p_promotor_id
        AND aps.active = true
    ) THEN
        RETURN QUERY SELECT false, 'You do not have access to this promotor.';
        RETURN;
    END IF;
    
    -- Determine new status
    IF p_action = 'approve' THEN
        v_new_status := 'approved';
    ELSIF p_action = 'reject' THEN
        v_new_status := 'rejected';
        IF p_rejection_reason IS NULL OR TRIM(p_rejection_reason) = '' THEN
            RETURN QUERY SELECT false, 'Rejection reason is required.';
            RETURN;
        END IF;
    ELSE
        RETURN QUERY SELECT false, 'Invalid action. Use approve or reject.';
        RETURN;
    END IF;
    
    -- Update schedules
    UPDATE schedules
    SET status = v_new_status,
        rejection_reason = CASE WHEN p_action = 'reject' THEN p_rejection_reason ELSE NULL END,
        updated_at = NOW()
    WHERE promotor_id = p_promotor_id
    AND month_year = p_month_year;
    
    IF p_action = 'approve' THEN
        RETURN QUERY SELECT true, 'Schedule approved successfully.';
    ELSE
        RETURN QUERY SELECT true, 'Schedule rejected. Promotor can now edit and resubmit.';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON COLUMN schedules.month_year IS 'Month grouping in YYYY-MM format for monthly submission';
COMMENT ON COLUMN schedules.rejection_reason IS 'Reason for rejection by SATOR (required when status = rejected)';
COMMENT ON FUNCTION copy_previous_month_schedule IS 'Copy previous month schedule to new month for promotor';
COMMENT ON FUNCTION get_sator_schedule_summary IS 'Get schedule status summary for all promotors under SATOR';
COMMENT ON FUNCTION submit_monthly_schedule IS 'Submit monthly schedule for approval';
COMMENT ON FUNCTION review_monthly_schedule IS 'Approve or reject monthly schedule (SATOR only)';
