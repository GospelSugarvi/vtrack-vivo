-- Fix get_sale_comments function - use correct table name
-- Drop all existing versions first
DROP FUNCTION IF EXISTS get_sale_comments(UUID);
DROP FUNCTION IF EXISTS get_sale_comments(UUID, INTEGER, INTEGER);

-- Create new version
CREATE OR REPLACE FUNCTION get_sale_comments(p_sale_id UUID)
RETURNS TABLE (
    comment_id UUID,
    user_id UUID,
    user_name TEXT,
    user_avatar TEXT,
    comment_text TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as comment_id,
        c.user_id,
        u.full_name as user_name,
        NULL::TEXT as user_avatar, -- Avatar not implemented yet
        c.comment_text,
        c.created_at
    FROM feed_comments c
    JOIN users u ON u.id = c.user_id
    WHERE c.sale_id = p_sale_id
    ORDER BY c.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
