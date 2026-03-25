-- Test SATOR schedule functions for Antonio

-- 1. Get Antonio's ID
SELECT id, full_name, role 
FROM users 
WHERE full_name ILIKE '%antonio%';

-- 2. Test get_sator_schedule_summary for current month
SELECT * FROM get_sator_schedule_summary(
    'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'::UUID, -- Antonio's ID
    TO_CHAR(NOW(), 'YYYY-MM') -- Current month (Feb 2026)
);

-- 3. Check if any promotors have schedules for Feb 2026
SELECT 
    u.full_name as promotor_name,
    s.name as store_name,
    sch.month_year,
    sch.status,
    COUNT(*) as schedule_count
FROM schedules sch
JOIN users u ON u.id = sch.promotor_id
JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
JOIN stores s ON s.id = aps.store_id
WHERE sch.month_year = TO_CHAR(NOW(), 'YYYY-MM')
GROUP BY u.full_name, s.name, sch.month_year, sch.status
ORDER BY u.full_name;

-- 4. Check Antonio's promotor assignments
SELECT 
    u.full_name as promotor_name,
    s.name as store_name,
    aps.active as promotor_active,
    ass.active as sator_active
FROM assignments_sator_store ass
JOIN stores s ON s.id = ass.store_id
JOIN assignments_promotor_store aps ON aps.store_id = s.id
JOIN users u ON u.id = aps.promotor_id
WHERE ass.sator_id = 'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'
AND u.role = 'promotor'
ORDER BY u.full_name, s.name;
