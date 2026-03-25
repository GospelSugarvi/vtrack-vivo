-- Check current logged in user and their targets

-- 1. Get current user info (ganti dengan user ID Anda yang sedang login)
SELECT 'Current user info:' as info;
SELECT id, email, full_name, role 
FROM auth.users 
LIMIT 5;

-- 2. Check if user has targets
SELECT 'User targets:' as info;
SELECT ut.*, tp.period_name, tp.start_date, tp.end_date
FROM user_targets ut
JOIN target_periods tp ON ut.period_id = tp.id
WHERE ut.user_id = (SELECT id FROM auth.users LIMIT 1);

-- 3. Check available periods
SELECT 'Available periods:' as info;
SELECT id, period_name, start_date, end_date
FROM target_periods
WHERE deleted_at IS NULL
ORDER BY start_date;

-- 4. Check promotor users with targets
SELECT 'Promotors with targets:' as info;
SELECT u.id, u.full_name, u.role, COUNT(ut.id) as target_count
FROM users u
LEFT JOIN user_targets ut ON u.id = ut.user_id
WHERE u.role = 'promotor' AND u.deleted_at IS NULL
GROUP BY u.id, u.full_name, u.role
ORDER BY target_count DESC
LIMIT 10;
