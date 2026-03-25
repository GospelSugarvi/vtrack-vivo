-- Fix get_sator_schedule_summary function
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
    SELECT 
        u.id as promotor_id,
        u.full_name as promotor_name,
        STRING_AGG(DISTINCT st.name, ', ') as store_name,
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
    JOIN stores st ON st.id = aps.store_id
    JOIN assignments_sator_store ass ON ass.store_id = st.id
    WHERE u.role = 'promotor'
    AND ass.sator_id = p_sator_id
    AND ass.active = true
    AND aps.active = true
    GROUP BY u.id, u.full_name
    ORDER BY u.full_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
