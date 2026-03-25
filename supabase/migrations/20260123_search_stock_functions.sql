-- Create search stock functions for promotor
-- This allows promotors to find stock in other stores within their area

-- Function to search stock in area (excluding current store)
-- Limited to stores handled by the same SATOR
CREATE OR REPLACE FUNCTION search_stock_in_area(
    p_product_id UUID,
    p_variant_id UUID,
    p_area TEXT,
    p_exclude_store_id UUID
)
RETURNS TABLE (
    store_id UUID,
    store_name TEXT,
    model_name TEXT,
    ram_rom TEXT,
    color TEXT,
    fresh_count BIGINT,
    chip_count BIGINT,
    display_count BIGINT,
    total_stock BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.store_id,
        st.store_name,
        p.model_name,
        pv.ram_rom,
        pv.color,
        COUNT(*) FILTER (WHERE s.tipe_stok = 'fresh' AND s.is_sold = false) as fresh_count,
        COUNT(*) FILTER (WHERE s.tipe_stok = 'chip' AND s.is_sold = false) as chip_count,
        COUNT(*) FILTER (WHERE s.tipe_stok = 'display' AND s.is_sold = false) as display_count,
        COUNT(*) FILTER (WHERE s.is_sold = false) as total_stock
    FROM stok s
    JOIN stores st ON s.store_id = st.id
    JOIN products p ON s.product_id = p.id
    JOIN product_variants pv ON s.variant_id = pv.id
    WHERE s.product_id = p_product_id
    AND s.variant_id = p_variant_id
    AND s.is_sold = false
    AND s.store_id != p_exclude_store_id
    AND EXISTS (
        -- Check if store is handled by the same SATOR as the requesting promotor
        SELECT 1 FROM assignments_promotor_store aps1
        JOIN hierarchy_sator_promotor hsp1 ON hsp1.promotor_id = aps1.promotor_id
        JOIN hierarchy_sator_promotor hsp2 ON hsp2.sator_id = hsp1.sator_id
        JOIN assignments_promotor_store aps2 ON aps2.promotor_id = hsp2.promotor_id
        WHERE aps1.promotor_id = auth.uid() -- Current promotor
        AND aps1.active = true
        AND hsp1.active = true
        AND hsp2.active = true
        AND aps2.active = true
        AND aps2.store_id = s.store_id -- Target store
    )
    GROUP BY s.store_id, st.store_name, p.model_name, pv.ram_rom, pv.color
    HAVING COUNT(*) FILTER (WHERE s.is_sold = false) > 0
    ORDER BY total_stock DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get transfer request summary for promotor
CREATE OR REPLACE FUNCTION get_transfer_requests_summary(p_promotor_id UUID)
RETURNS JSON AS $$
DECLARE
    v_summary JSON;
BEGIN
    SELECT json_build_object(
        'total_requests', COUNT(*),
        'pending_requests', COUNT(*) FILTER (WHERE status = 'pending'),
        'approved_requests', COUNT(*) FILTER (WHERE status = 'approved'),
        'rejected_requests', COUNT(*) FILTER (WHERE status = 'rejected'),
        'received_requests', COUNT(*) FILTER (WHERE status = 'received'),
        'last_request_date', MAX(requested_at)
    ) INTO v_summary
    FROM stock_transfer_requests
    WHERE requested_by = p_promotor_id;
    
    RETURN v_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if transfer is allowed between stores
-- Only allow transfers within same SATOR's stores
CREATE OR REPLACE FUNCTION can_request_transfer(
    p_from_store_id UUID,
    p_to_store_id UUID,
    p_promotor_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_same_sator BOOLEAN := false;
BEGIN
    -- Check if both stores are handled by the same SATOR as the requesting promotor
    SELECT EXISTS (
        -- Get SATOR of requesting promotor
        SELECT 1 FROM assignments_promotor_store aps1
        JOIN hierarchy_sator_promotor hsp1 ON hsp1.promotor_id = aps1.promotor_id
        WHERE aps1.promotor_id = p_promotor_id
        AND aps1.active = true
        AND hsp1.active = true
        
        -- Check if from_store is handled by same SATOR
        AND EXISTS (
            SELECT 1 FROM assignments_promotor_store aps2
            JOIN hierarchy_sator_promotor hsp2 ON hsp2.promotor_id = aps2.promotor_id
            WHERE aps2.store_id = p_from_store_id
            AND aps2.active = true
            AND hsp2.active = true
            AND hsp2.sator_id = hsp1.sator_id
        )
        
        -- Check if to_store is handled by same SATOR
        AND EXISTS (
            SELECT 1 FROM assignments_promotor_store aps3
            JOIN hierarchy_sator_promotor hsp3 ON hsp3.promotor_id = aps3.promotor_id
            WHERE aps3.store_id = p_to_store_id
            AND aps3.active = true
            AND hsp3.active = true
            AND hsp3.sator_id = hsp1.sator_id
        )
    ) INTO v_same_sator;
    
    -- Also ensure stores are different
    RETURN v_same_sator AND p_from_store_id != p_to_store_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION search_stock_in_area TO authenticated;
GRANT EXECUTE ON FUNCTION get_transfer_requests_summary TO authenticated;
GRANT EXECUTE ON FUNCTION can_request_transfer TO authenticated;

-- Add comments
COMMENT ON FUNCTION search_stock_in_area IS 'Search available stock in stores handled by same SATOR (not cross-SATOR)';
COMMENT ON FUNCTION get_transfer_requests_summary IS 'Get summary of transfer requests for a promotor';
COMMENT ON FUNCTION can_request_transfer IS 'Check if transfer request is allowed between stores (same SATOR only)';