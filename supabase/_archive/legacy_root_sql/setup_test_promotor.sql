-- ==========================================
-- SETUP TEST PROMOTOR WITH TARGET
-- ==========================================

-- Step 1: Check existing promotors
SELECT '=== EXISTING PROMOTORS ===' as step;
SELECT 
    u.id,
    u.email,
    u.full_name,
    u.role,
    u.area,
    COUNT(ut.id) as target_count
FROM users u
LEFT JOIN user_targets ut ON u.id = ut.user_id
WHERE u.role = 'promotor' 
AND u.deleted_at IS NULL
GROUP BY u.id, u.email, u.full_name, u.role, u.area
ORDER BY u.full_name
LIMIT 10;

-- Step 2: Check available periods
SELECT '=== AVAILABLE PERIODS ===' as step;
SELECT id, period_name, start_date, end_date
FROM target_periods
WHERE deleted_at IS NULL
ORDER BY start_date;

-- Step 3: Check available fokus bundles
SELECT '=== AVAILABLE FOKUS BUNDLES ===' as step;
SELECT id, bundle_name, product_types
FROM fokus_bundles
WHERE deleted_at IS NULL
ORDER BY bundle_name;

-- ==========================================
-- PILIH SALAH SATU PROMOTOR DI ATAS
-- Ganti 'PROMOTOR-ID-HERE' dengan ID promotor dari query pertama
-- Ganti 'PERIOD-ID-HERE' dengan ID period dari query kedua
-- ==========================================

-- Step 4: Set target untuk promotor (UNCOMMENT dan ganti ID)
/*
-- Set target omzet dan fokus total
INSERT INTO user_targets (user_id, period_id, target_omzet, target_fokus_total)
VALUES (
    'PROMOTOR-ID-HERE',  -- Ganti dengan ID promotor
    'PERIOD-ID-HERE',     -- Ganti dengan ID period (Januari 2026)
    50000000,             -- Target omzet: 50 juta
    30                    -- Target fokus total: 30 unit
)
ON CONFLICT (user_id, period_id) 
DO UPDATE SET 
    target_omzet = EXCLUDED.target_omzet,
    target_fokus_total = EXCLUDED.target_fokus_total;

-- Set fokus target per bundle (UNCOMMENT dan ganti ID)
-- Contoh: Bundle A54/A34 target 15 unit, Bundle A15 target 15 unit
INSERT INTO fokus_targets (user_id, period_id, bundle_id, target_qty)
VALUES 
    ('PROMOTOR-ID-HERE', 'PERIOD-ID-HERE', 'BUNDLE-ID-1', 15),
    ('PROMOTOR-ID-HERE', 'PERIOD-ID-HERE', 'BUNDLE-ID-2', 15)
ON CONFLICT (user_id, period_id, bundle_id)
DO UPDATE SET target_qty = EXCLUDED.target_qty;
*/

-- Step 5: Verify target was set
SELECT '=== VERIFY TARGET ===' as step;
-- SELECT * FROM user_targets WHERE user_id = 'PROMOTOR-ID-HERE';
-- SELECT * FROM fokus_targets WHERE user_id = 'PROMOTOR-ID-HERE';

-- ==========================================
-- ALTERNATIVE: CREATE NEW TEST PROMOTOR
-- ==========================================
/*
-- This will be created via Edge Function create-user
-- You need to call it from your app or use Supabase dashboard

POST https://your-project.supabase.co/functions/v1/create-user
{
  "email": "test.promotor@vtrack.com",
  "password": "Test123!",
  "full_name": "Test Promotor",
  "role": "promotor",
  "area": "Kupang"
}

-- After creating, get the user ID and set targets using the INSERT statements above
*/

-- ==========================================
-- QUICK OPTION: Get promotor credentials
-- ==========================================
SELECT '=== PROMOTOR INFO FOR LOGIN ===' as step;
SELECT 
    'Email: ' || u.email as info,
    'Name: ' || u.full_name as name,
    'Role: ' || u.role as role,
    'Note: Password was set during user creation' as note
FROM users u
WHERE u.role = 'promotor' 
AND u.deleted_at IS NULL
LIMIT 1;
