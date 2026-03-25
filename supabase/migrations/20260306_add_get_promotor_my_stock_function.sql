-- Function to get promotor's own store stock (realtime)
-- Shows current physical stock count per variant
-- Created: 2026-03-06

CREATE OR REPLACE FUNCTION get_promotor_my_stock(p_promotor_id UUID)
RETURNS TABLE (
    product_id UUID,
    variant_id UUID,
    model_name TEXT,
    series TEXT,
    ram_rom TEXT,
    color TEXT,
    total_stock BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.product_id,
        s.variant_id,
        p.model_name::TEXT,
        p.series::TEXT,
        pv.ram_rom::TEXT,
        pv.color::TEXT,
        COUNT(*)::BIGINT AS total_stock
    FROM stok s
    JOIN products p ON s.product_id = p.id
    JOIN product_variants pv ON s.variant_id = pv.id
    WHERE s.promotor_id = p_promotor_id
    AND s.is_sold = false
    GROUP BY s.product_id, s.variant_id, p.model_name, p.series, pv.ram_rom, pv.color
    ORDER BY total_stock DESC, p.model_name ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_promotor_my_stock TO authenticated;

-- Add comment
COMMENT ON FUNCTION get_promotor_my_stock IS 'Get promotor''s current physical stock count (unsold items only)';
