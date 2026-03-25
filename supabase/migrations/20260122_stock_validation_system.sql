-- Create stock validation system
-- Drop existing tables if they exist
DROP TABLE IF EXISTS stock_validation_items CASCADE;
DROP TABLE IF EXISTS stock_validations CASCADE;

-- Create stock validations table
CREATE TABLE stock_validations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    validation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_items INTEGER NOT NULL DEFAULT 0,
    validated_items INTEGER NOT NULL DEFAULT 0,
    corrections_made INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'cancelled')),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create stock validation items (detailed records)
CREATE TABLE stock_validation_items (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    validation_id UUID NOT NULL REFERENCES stock_validations(id) ON DELETE CASCADE,
    stok_id UUID NOT NULL REFERENCES stok(id),
    imei TEXT NOT NULL,
    original_condition TEXT NOT NULL CHECK (original_condition IN ('fresh', 'chip', 'display')),
    validated_condition TEXT NOT NULL CHECK (validated_condition IN ('fresh', 'chip', 'display')),
    is_present BOOLEAN NOT NULL DEFAULT true,
    correction_note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for better performance
CREATE INDEX idx_stock_validations_promotor ON stock_validations(promotor_id);
CREATE INDEX idx_stock_validations_date ON stock_validations(validation_date);
CREATE INDEX idx_stock_validation_items_validation ON stock_validation_items(validation_id);
CREATE INDEX idx_stock_validation_items_stok ON stock_validation_items(stok_id);

-- Add RLS policies
ALTER TABLE stock_validations ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_validation_items ENABLE ROW LEVEL SECURITY;

-- Promotor can only manage their own validations
CREATE POLICY "Promotor can manage own validations" ON stock_validations
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- Promotor can only manage validation items for their own validations
CREATE POLICY "Promotor can manage own validation items" ON stock_validation_items
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM stock_validations sv
            WHERE sv.id = stock_validation_items.validation_id
            AND sv.promotor_id = auth.uid()
        )
    );

-- SATOR can view validations from their team promotors
CREATE POLICY "SATOR can view team validations" ON stock_validations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = stock_validations.promotor_id
            AND hsp.active = true
        )
    );

-- SATOR can view validation items from their team
CREATE POLICY "SATOR can view team validation items" ON stock_validation_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM stock_validations sv
            JOIN users u ON u.id = sv.promotor_id
            JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = u.id
            WHERE sv.id = stock_validation_items.validation_id
            AND hsp.sator_id = auth.uid()
            AND hsp.active = true
        )
    );

-- SPV can view validations in their area
CREATE POLICY "SPV can view area validations" ON stock_validations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = stock_validations.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

-- Admin can manage all validations
CREATE POLICY "Admin can manage all validations" ON stock_validations
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

CREATE POLICY "Admin can manage all validation items" ON stock_validation_items
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_stock_validations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_stock_validations_updated_at
    BEFORE UPDATE ON stock_validations
    FOR EACH ROW
    EXECUTE FUNCTION update_stock_validations_updated_at();

-- Function to get validation summary for promotor
CREATE OR REPLACE FUNCTION get_validation_summary(p_promotor_id UUID, p_date DATE DEFAULT CURRENT_DATE)
RETURNS JSON AS $$
DECLARE
    v_validation RECORD;
    v_summary JSON;
BEGIN
    -- Get latest validation for the date
    SELECT * INTO v_validation
    FROM stock_validations 
    WHERE promotor_id = p_promotor_id 
    AND validation_date = p_date
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN json_build_object(
            'has_validation', false,
            'message', 'No validation found for this date'
        );
    END IF;
    
    -- Build summary
    v_summary := json_build_object(
        'has_validation', true,
        'validation_id', v_validation.id,
        'status', v_validation.status,
        'total_items', v_validation.total_items,
        'validated_items', v_validation.validated_items,
        'corrections_made', v_validation.corrections_made,
        'validation_date', v_validation.validation_date,
        'completion_percentage', 
        CASE 
            WHEN v_validation.total_items > 0 THEN 
                ROUND((v_validation.validated_items::DECIMAL / v_validation.total_items) * 100, 1)
            ELSE 0 
        END
    );
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if validation is required today
CREATE OR REPLACE FUNCTION is_validation_required(p_promotor_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_last_validation DATE;
    v_required BOOLEAN := false;
BEGIN
    -- Get last validation date
    SELECT validation_date INTO v_last_validation
    FROM stock_validations 
    WHERE promotor_id = p_promotor_id 
    AND status = 'completed'
    ORDER BY validation_date DESC
    LIMIT 1;
    
    -- Check if validation is required (daily validation rule)
    IF v_last_validation IS NULL OR v_last_validation < CURRENT_DATE THEN
        v_required := true;
    END IF;
    
    RETURN v_required;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE stock_validations IS 'Daily stock validation records by promotors';
COMMENT ON TABLE stock_validation_items IS 'Detailed validation items with IMEI-level tracking';
COMMENT ON FUNCTION get_validation_summary IS 'Get validation summary for a promotor on specific date';
COMMENT ON FUNCTION is_validation_required IS 'Check if stock validation is required for promotor today';