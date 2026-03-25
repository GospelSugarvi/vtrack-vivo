-- Create search stock functions for promotor with SATOR ID check
-- This allows promotors to find stock in other stores within their SATOR TEAM

-- Drop old function to update signature
DROP FUNCTION IF EXISTS search_stock_in_area(UUID, UUID, TEXT, UUID);

-- Function to search stock in area (excluding current store)
-- Limited to stores handled by the same SATOR
-- Parameter p_sator_id is now required to filter stores under the same SATOR
CREATE OR REPLACE FUNCTION search_stock_in_area(
    p_product_id UUID,
    p_variant_id UUID,
    p_area TEXT,
    p_sator_id UUID,
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
        -- Check if target store is handled by a promotor under the SAME SATOR
        SELECT 1 FROM assignments_promotor_store aps
        JOIN users u ON u.id = aps.promotor_id
        WHERE aps.store_id = s.store_id
        AND aps.active = true
        AND u.sator_id = p_sator_id -- Filtering by SATOR ID here
    )
    GROUP BY s.store_id, st.store_name, p.model_name, pv.ram_rom, pv.color
    HAVING COUNT(*) FILTER (WHERE s.is_sold = false) > 0
    ORDER BY total_stock DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION search_stock_in_area TO authenticated;

COMMENT ON FUNCTION search_stock_in_area IS 'Search available stock in stores handled by same SATOR (using users.sator_id)';
