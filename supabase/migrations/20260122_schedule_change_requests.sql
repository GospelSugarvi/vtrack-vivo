-- Add change request system for approved schedules
CREATE TABLE schedule_change_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    original_schedule_id UUID NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
    requested_date DATE NOT NULL,
    original_shift_type TEXT NOT NULL CHECK (original_shift_type IN ('pagi', 'siang', 'libur')),
    requested_shift_type TEXT NOT NULL CHECK (requested_shift_type IN ('pagi', 'siang', 'libur')),
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    sator_comment TEXT,
    sator_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add new status to schedules table
ALTER TABLE schedules ADD COLUMN change_request_id UUID REFERENCES schedule_change_requests(id);

-- Add indexes
CREATE INDEX idx_schedule_change_requests_promotor ON schedule_change_requests(promotor_id);
CREATE INDEX idx_schedule_change_requests_status ON schedule_change_requests(status);
CREATE INDEX idx_schedule_change_requests_date ON schedule_change_requests(requested_date);

-- Add RLS policies
ALTER TABLE schedule_change_requests ENABLE ROW LEVEL SECURITY;

-- Promotor can create and view their own change requests
CREATE POLICY "Promotor can manage own change requests" ON schedule_change_requests
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- SATOR can view and approve change requests from their team
CREATE POLICY "SATOR can manage team change requests" ON schedule_change_requests
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = schedule_change_requests.promotor_id
            AND hsp.active = true
        )
    );

-- SPV can view change requests in their area
CREATE POLICY "SPV can view area change requests" ON schedule_change_requests
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = schedule_change_requests.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

-- Admin can manage all change requests
CREATE POLICY "Admin can manage all change requests" ON schedule_change_requests
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_schedule_change_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_schedule_change_requests_updated_at
    BEFORE UPDATE ON schedule_change_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_schedule_change_requests_updated_at();

-- Function to request schedule change
CREATE OR REPLACE FUNCTION request_schedule_change(
    p_promotor_id UUID,
    p_schedule_date DATE,
    p_new_shift_type TEXT,
    p_reason TEXT
)
RETURNS JSON AS $$
DECLARE
    v_schedule RECORD;
    v_change_request_id UUID;
    v_result JSON;
BEGIN
    -- Get existing schedule
    SELECT * INTO v_schedule
    FROM schedules 
    WHERE promotor_id = p_promotor_id 
    AND schedule_date = p_schedule_date;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Schedule not found');
    END IF;
    
    -- Check if schedule is approved
    IF v_schedule.status != 'approved' THEN
        RETURN json_build_object('success', false, 'error', 'Can only request changes for approved schedules');
    END IF;
    
    -- Check if same shift type
    IF v_schedule.shift_type = p_new_shift_type THEN
        RETURN json_build_object('success', false, 'error', 'New shift type is same as current');
    END IF;
    
    -- Create change request
    INSERT INTO schedule_change_requests (
        promotor_id,
        original_schedule_id,
        requested_date,
        original_shift_type,
        requested_shift_type,
        reason,
        status
    ) VALUES (
        p_promotor_id,
        v_schedule.id,
        p_schedule_date,
        v_schedule.shift_type,
        p_new_shift_type,
        p_reason,
        'pending'
    ) RETURNING id INTO v_change_request_id;
    
    -- Update schedule to reference change request
    UPDATE schedules 
    SET change_request_id = v_change_request_id
    WHERE id = v_schedule.id;
    
    RETURN json_build_object(
        'success', true, 
        'change_request_id', v_change_request_id,
        'message', 'Change request submitted successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to approve/reject schedule change
CREATE OR REPLACE FUNCTION process_schedule_change(
    p_change_request_id UUID,
    p_sator_id UUID,
    p_action TEXT, -- 'approve' or 'reject'
    p_comment TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_change_request RECORD;
    v_result JSON;
BEGIN
    -- Get change request
    SELECT * INTO v_change_request
    FROM schedule_change_requests 
    WHERE id = p_change_request_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Change request not found');
    END IF;
    
    -- Check if still pending
    IF v_change_request.status != 'pending' THEN
        RETURN json_build_object('success', false, 'error', 'Change request already processed');
    END IF;
    
    -- Update change request
    UPDATE schedule_change_requests 
    SET 
        status = p_action,
        sator_id = p_sator_id,
        sator_comment = p_comment,
        updated_at = NOW()
    WHERE id = p_change_request_id;
    
    -- If approved, update the original schedule
    IF p_action = 'approved' THEN
        UPDATE schedules 
        SET 
            shift_type = v_change_request.requested_shift_type,
            updated_at = NOW()
        WHERE id = v_change_request.original_schedule_id;
    END IF;
    
    -- Clear change request reference from schedule
    UPDATE schedules 
    SET change_request_id = NULL
    WHERE change_request_id = p_change_request_id;
    
    RETURN json_build_object(
        'success', true,
        'action', p_action,
        'message', 'Change request ' || p_action || ' successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE schedule_change_requests IS 'Change requests for approved schedules';
COMMENT ON FUNCTION request_schedule_change IS 'Submit a change request for approved schedule';
COMMENT ON FUNCTION process_schedule_change IS 'Approve or reject a schedule change request';