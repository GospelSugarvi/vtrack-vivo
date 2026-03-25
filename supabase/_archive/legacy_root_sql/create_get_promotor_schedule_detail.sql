-- Function to get promotor schedule detail for review

CREATE OR REPLACE FUNCTION get_promotor_schedule_detail(
    p_promotor_id UUID,
    p_month_year TEXT -- Format: 'YYYY-MM'
)
RETURNS TABLE (
    schedule_date DATE,
    shift_type TEXT,
    status TEXT,
    rejection_reason TEXT,
    promotor_name TEXT,
    store_name TEXT,
    total_days INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.schedule_date,
        s.shift_type,
        s.status,
        s.rejection_reason,
        u.full_name as promotor_name,
        st.store_name,
        (SELECT COUNT(*)::INTEGER FROM schedules WHERE promotor_id = p_promotor_id AND month_year = p_month_year) as total_days
    FROM schedules s
    JOIN users u ON u.id = s.promotor_id
    LEFT JOIN assignments_promotor_store aps ON aps.promotor_id = u.id AND aps.active = true
    LEFT JOIN stores st ON st.id = aps.store_id
    WHERE s.promotor_id = p_promotor_id
    AND s.month_year = p_month_year
    ORDER BY s.schedule_date;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_promotor_schedule_detail IS 'Get detailed schedule for a promotor in a specific month for SATOR review';

-- Test the function with Yohanis (who has submitted schedule)
SELECT * FROM get_promotor_schedule_detail(
    'a85b7470-47f8-481c-9dd0-d77ad851b4a7'::UUID, -- Yohanis
    '2026-02'
);
