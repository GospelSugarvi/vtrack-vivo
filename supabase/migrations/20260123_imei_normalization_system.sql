-- IMEI Normalization System
-- Based on docs/03_UI_PROMOTOR_ROLE.md and docs/03_UI_SATOR_ROLE.md

-- Add normalization flag to stores table
ALTER TABLE stores ADD COLUMN IF NOT EXISTS needs_imei_normalization BOOLEAN DEFAULT false;

-- Create IMEI normalization tracking table
CREATE TABLE imei_normalizations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    promotor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id UUID NOT NULL REFERENCES stores(id),
    imei TEXT NOT NULL,
    product_id UUID NOT NULL REFERENCES products(id),
    variant_id UUID NOT NULL REFERENCES product_variants(id),
    
    -- Status flow: pending → sent → normalized → scanned
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'normalized', 'scanned')),
    
    -- Timestamps for each stage
    sold_at TIMESTAMPTZ NOT NULL, -- When the sale happened
    sent_to_sator_at TIMESTAMPTZ, -- When promotor confirmed to send to SATOR
    normalized_at TIMESTAMPTZ, -- When SATOR marked as normalized
    scanned_at TIMESTAMPTZ, -- When promotor scanned in vChat
    
    -- Additional info
    sator_id UUID REFERENCES users(id), -- SATOR who normalized
    notes TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(imei, sold_at) -- Prevent duplicate entries for same IMEI sale
);

-- Add indexes
CREATE INDEX idx_imei_normalizations_promotor ON imei_normalizations(promotor_id);
CREATE INDEX idx_imei_normalizations_status ON imei_normalizations(status);
CREATE INDEX idx_imei_normalizations_store ON imei_normalizations(store_id);
CREATE INDEX idx_imei_normalizations_imei ON imei_normalizations(imei);
CREATE INDEX idx_imei_normalizations_sold_at ON imei_normalizations(sold_at);

-- Add RLS policies
ALTER TABLE imei_normalizations ENABLE ROW LEVEL SECURITY;

-- Promotor can manage their own IMEI normalizations
CREATE POLICY "Promotor can manage own IMEI normalizations" ON imei_normalizations
    FOR ALL USING (
        auth.uid() = promotor_id AND
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'promotor'
        )
    );

-- SATOR can view and update IMEI normalizations from their team
CREATE POLICY "SATOR can manage team IMEI normalizations" ON imei_normalizations
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN hierarchy_sator_promotor hsp ON hsp.sator_id = u.id
            WHERE u.id = auth.uid() 
            AND u.role = 'sator'
            AND hsp.promotor_id = imei_normalizations.promotor_id
            AND hsp.active = true
        )
    );

-- SPV can view IMEI normalizations in their area
CREATE POLICY "SPV can view area IMEI normalizations" ON imei_normalizations
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM users u
            JOIN users p ON p.id = imei_normalizations.promotor_id
            WHERE u.id = auth.uid() 
            AND u.role = 'spv'
            AND u.area = p.area
        )
    );

-- Admin can manage all IMEI normalizations
CREATE POLICY "Admin can manage all IMEI normalizations" ON imei_normalizations
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM users 
            WHERE id = auth.uid() 
            AND role = 'admin'
        )
    );

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_imei_normalizations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_imei_normalizations_updated_at
    BEFORE UPDATE ON imei_normalizations
    FOR EACH ROW
    EXECUTE FUNCTION update_imei_normalizations_updated_at();

-- Function to create IMEI normalization record (called during sell-out)
CREATE OR REPLACE FUNCTION create_imei_normalization(
    p_promotor_id UUID,
    p_store_id UUID,
    p_imei TEXT,
    p_product_id UUID,
    p_variant_id UUID
)
RETURNS JSON AS $$
DECLARE
    v_needs_normalization BOOLEAN;
    v_normalization_id UUID;
BEGIN
    -- Check if store needs IMEI normalization
    SELECT needs_imei_normalization INTO v_needs_normalization
    FROM stores
    WHERE id = p_store_id;
    
    -- If store doesn't need normalization, return success without creating record
    IF NOT v_needs_normalization THEN
        RETURN json_build_object(
            'success', true,
            'needs_normalization', false,
            'message', 'Store does not require IMEI normalization'
        );
    END IF;
    
    -- Create normalization record
    INSERT INTO imei_normalizations (
        promotor_id,
        store_id,
        imei,
        product_id,
        variant_id,
        status,
        sold_at
    ) VALUES (
        p_promotor_id,
        p_store_id,
        p_imei,
        p_product_id,
        p_variant_id,
        'pending',
        NOW()
    ) RETURNING id INTO v_normalization_id;
    
    RETURN json_build_object(
        'success', true,
        'needs_normalization', true,
        'normalization_id', v_normalization_id,
        'message', 'IMEI normalization record created'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to send IMEI to SATOR (promotor confirms)
CREATE OR REPLACE FUNCTION send_imei_to_sator(p_normalization_id UUID)
RETURNS JSON AS $$
BEGIN
    -- Update status to sent
    UPDATE imei_normalizations
    SET 
        status = 'sent',
        sent_to_sator_at = NOW()
    WHERE id = p_normalization_id
    AND status = 'pending';
    
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'IMEI normalization record not found or already processed'
        );
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'message', 'IMEI sent to SATOR for normalization'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark IMEI as normalized (SATOR action)
CREATE OR REPLACE FUNCTION mark_imei_normalized(
    p_normalization_id UUID,
    p_sator_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON AS $$
BEGIN
    -- Update status to normalized
    UPDATE imei_normalizations
    SET 
        status = 'normalized',
        normalized_at = NOW(),
        sator_id = p_sator_id,
        notes = p_notes
    WHERE id = p_normalization_id
    AND status = 'sent';
    
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'IMEI normalization record not found or not in sent status'
        );
    END IF;
    
    -- TODO: Send push notification to promotor
    
    RETURN json_build_object(
        'success', true,
        'message', 'IMEI marked as normalized'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to mark IMEI as scanned (promotor confirms scan in vChat)
CREATE OR REPLACE FUNCTION mark_imei_scanned(p_normalization_id UUID)
RETURNS JSON AS $$
BEGIN
    -- Update status to scanned
    UPDATE imei_normalizations
    SET 
        status = 'scanned',
        scanned_at = NOW()
    WHERE id = p_normalization_id
    AND status = 'normalized';
    
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'IMEI normalization record not found or not normalized yet'
        );
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'message', 'IMEI marked as scanned'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get IMEI normalization summary for promotor
CREATE OR REPLACE FUNCTION get_imei_normalization_summary(p_promotor_id UUID)
RETURNS JSON AS $$
DECLARE
    v_summary JSON;
BEGIN
    SELECT json_build_object(
        'total_imei', COUNT(*),
        'pending_count', COUNT(*) FILTER (WHERE status = 'pending'),
        'sent_count', COUNT(*) FILTER (WHERE status = 'sent'),
        'normalized_count', COUNT(*) FILTER (WHERE status = 'normalized'),
        'scanned_count', COUNT(*) FILTER (WHERE status = 'scanned'),
        'needs_action', COUNT(*) FILTER (WHERE status IN ('pending', 'normalized')) > 0
    ) INTO v_summary
    FROM imei_normalizations
    WHERE promotor_id = p_promotor_id;
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION create_imei_normalization TO authenticated;
GRANT EXECUTE ON FUNCTION send_imei_to_sator TO authenticated;
GRANT EXECUTE ON FUNCTION mark_imei_normalized TO authenticated;
GRANT EXECUTE ON FUNCTION mark_imei_scanned TO authenticated;
GRANT EXECUTE ON FUNCTION get_imei_normalization_summary TO authenticated;

-- Add comments
COMMENT ON TABLE imei_normalizations IS 'IMEI normalization tracking for stores that require it';
COMMENT ON FUNCTION create_imei_normalization IS 'Create IMEI normalization record during sell-out';
COMMENT ON FUNCTION send_imei_to_sator IS 'Promotor confirms sending IMEI to SATOR';
COMMENT ON FUNCTION mark_imei_normalized IS 'SATOR marks IMEI as normalized';
COMMENT ON FUNCTION mark_imei_scanned IS 'Promotor confirms IMEI scanned in vChat';
COMMENT ON FUNCTION get_imei_normalization_summary IS 'Get IMEI normalization summary for promotor';

-- Sample data: Mark some stores as needing normalization
UPDATE stores SET needs_imei_normalization = true WHERE store_name ILIKE '%giant%' OR store_name ILIKE '%transmart%';