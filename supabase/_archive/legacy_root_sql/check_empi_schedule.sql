-- Check Empi's schedule and relationship with Antonio

-- 1. Get Empi's info
SELECT id, full_name, email, area, role
FROM users
WHERE email ILIKE '%empi%' OR full_name ILIKE '%empi%';

-- 2. Check Empi's schedules
SELECT 
    s.id,
    s.promotor_id,
    u.full_name as promotor_name,
    s.month_year,
    s.status,
    COUNT(*) as total_days
FROM schedules s
JOIN users u ON u.id = s.promotor_id
WHERE u.full_name ILIKE '%empi%'
GROUP BY s.id, s.promotor_id, u.full_name, s.month_year, s.status
ORDER BY s.month_year DESC;

-- 3. Check Empi's store assignment
SELECT 
    u.full_name as promotor_name,
    st.store_name,
    aps.active as promotor_active
FROM users u
JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
JOIN stores st ON st.id = aps.store_id
WHERE u.full_name ILIKE '%empi%';

-- 4. Check if Antonio is assigned to Empi's store
SELECT 
    u.full_name as promotor_name,
    st.store_name,
    sator.full_name as sator_name,
    ass.active as sator_active
FROM users u
JOIN assignments_promotor_store aps ON aps.promotor_id = u.id
JOIN stores st ON st.id = aps.store_id
LEFT JOIN assignments_sator_store ass ON ass.store_id = st.id
LEFT JOIN users sator ON sator.id = ass.sator_id
WHERE u.full_name ILIKE '%empi%';

-- 5. Check hierarchy_sator_promotor
SELECT 
    sator.full_name as sator_name,
    promotor.full_name as promotor_name,
    hsp.active
FROM hierarchy_sator_promotor hsp
JOIN users sator ON sator.id = hsp.sator_id
JOIN users promotor ON promotor.id = hsp.promotor_id
WHERE promotor.full_name ILIKE '%empi%';

-- 6. Test get_sator_schedule_summary for Antonio with current month
SELECT * FROM get_sator_schedule_summary(
    'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'::UUID, -- Antonio
    TO_CHAR(NOW(), 'YYYY-MM')
)
WHERE promotor_name ILIKE '%empi%';
