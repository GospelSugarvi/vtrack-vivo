-- Revert search_stock_in_area to use hierarchy table and remove manual sator_id parameter
-- Logic: The function automatically finds the SATOR of the current user (auth.uid()) and filters stores accordingly.

DROP FUNCTION IF EXISTS search_stock_in_area(UUID, UUID, TEXT, UUID, UUID); -- Drop the wrong V2 func we just made
DROP FUNCTION IF EXISTS search_stock_in_area(UUID, UUID, TEXT, UUID); -- Drop original just in case

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
DECLARE
    v_current_sator_id UUID;
BEGIN
    -- 1. Find the active SATOR for the current logged-in promotor
    SELECT sator_id INTO v_current_sator_id
    FROM hierarchy_sator_promotor
    WHERE promotor_id = auth.uid()
    AND active = true
    LIMIT 1;

    -- If no SATOR found, return empty (or handle as error if preferred)
    IF v_current_sator_id IS NULL THEN
        RETURN;
    END IF;

    -- 2. Return stock from stores handled by promotor under the SAME SATOR
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
    -- Join to find the SATOR of the store owner
    JOIN assignments_promotor_store aps ON s.store_id = aps.store_id AND aps.active = true
    JOIN hierarchy_sator_promotor hsp ON aps.promotor_id = hsp.promotor_id AND hsp.active = true
    WHERE s.product_id = p_product_id
    AND s.variant_id = p_variant_id
    AND s.is_sold = false
    AND s.store_id != p_exclude_store_id
    -- Filter: Only show stores where the promotor's SATOR is the same as current user's SATOR
    AND hsp.sator_id = v_current_sator_id
    
    GROUP BY s.store_id, st.store_name, p.model_name, pv.ram_rom, pv.color
    HAVING COUNT(*) FILTER (WHERE s.is_sold = false) > 0
    ORDER BY total_stock DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION search_stock_in_area TO authenticated;

-- Cleanup: Remove the temporary sator_id column from users if desired
ALTER TABLE users DROP COLUMN IF EXISTS sator_id;
