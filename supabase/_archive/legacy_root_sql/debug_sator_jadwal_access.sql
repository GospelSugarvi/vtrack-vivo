-- Debug why Sator Jadwal page shows 0 schedules

-- 1. Check if function exists and is accessible
SELECT 
    p.proname as function_name,
    pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'get_sator_schedule_summary';

-- 2. Test function directly with Antonio's ID
SELECT * FROM get_sator_schedule_summary(
    'a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb'::UUID,
    '2026-02'
);

-- 3. Check RLS policies on schedules table
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'schedules';

-- 4. Verify Antonio can see schedules through RLS
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub": "a7c3a57a-bb3b-47ac-a33c-5e46eee79aeb", "role": "authenticated"}';

SELECT 
    s.id,
    s.promotor_id,
    u.full_name as promotor_name,
    s.schedule_date,
    s.month_year,
    s.status,
    s.shift_type
FROM schedules s
JOIN users u ON u.id = s.promotor_id
WHERE s.month_year = '2026-02'
LIMIT 10;

RESET role;
