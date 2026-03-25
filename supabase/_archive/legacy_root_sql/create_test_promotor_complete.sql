-- ==========================================
-- CREATE TEST PROMOTOR WITH COMPLETE SETUP
-- Run this to create a test promotor you can login with
-- ==========================================

-- This creates a promotor in the users table
-- You'll need to create the auth user separately via Supabase Dashboard or Edge Function

DO $$
DECLARE
    v_period_id UUID;
    v_bundle_id_1 UUID;
    v_bundle_id_2 UUID;
    v_test_user_id UUID := '00000000-0000-0000-0000-000000000001'; -- Placeholder, replace with actual auth user ID
BEGIN
    -- Get current period (Januari 2026)
    SELECT id INTO v_period_id
    FROM target_periods
    WHERE period_name = 'Januari 2026'
    AND deleted_at IS NULL
    LIMIT 1;

    -- Get first two bundles
    SELECT id INTO v_bundle_id_1
    FROM fokus_bundles
    WHERE deleted_at IS NULL
    ORDER BY bundle_name
    LIMIT 1;

    SELECT id INTO v_bundle_id_2
    FROM fokus_bundles
    WHERE deleted_at IS NULL
    ORDER BY bundle_name
    OFFSET 1
    LIMIT 1;

    RAISE NOTICE 'Period ID: %', v_period_id;
    RAISE NOTICE 'Bundle 1 ID: %', v_bundle_id_1;
    RAISE NOTICE 'Bundle 2 ID: %', v_bundle_id_2;
    RAISE NOTICE 'Test User ID: %', v_test_user_id;
    
    -- Note: You need to create auth user first via Supabase Dashboard:
    -- 1. Go to Authentication > Users
    -- 2. Click "Add User"
    -- 3. Email: test.promotor@vtrack.com
    -- 4. Password: Test123!
    -- 5. Copy the generated UUID
    -- 6. Replace v_test_user_id above with that UUID
    -- 7. Then run this script
    
END $$;

-- ==========================================
-- MANUAL STEPS TO CREATE TEST PROMOTOR:
-- ==========================================

/*
STEP 1: Create auth user in Supabase Dashboard
- Go to: Authentication > Users > Add User
- Email: test.promotor@vtrack.com
- Password: Test123!
- Auto Confirm User: YES
- Copy the generated User ID

STEP 2: Insert into users table (replace USER-ID with the one from step 1)
*/

-- UNCOMMENT and replace USER-ID-FROM-STEP-1:
/*
INSERT INTO users (id, email, full_name, role, area, phone)
VALUES (
    'USER-ID-FROM-STEP-1',
    'test.promotor@vtrack.com',
    'Test Promotor',
    'promotor',
    'Kupang',
    '081234567890'
);
*/

/*
STEP 3: Set targets (replace USER-ID and get PERIOD-ID from query below)
*/

-- Get period ID first:
SELECT 'Copy this Period ID:' as note, id, period_name 
FROM target_periods 
WHERE period_name = 'Januari 2026' 
AND deleted_at IS NULL;

-- Get bundle IDs:
SELECT 'Copy these Bundle IDs:' as note, id, bundle_name, product_types
FROM fokus_bundles
WHERE deleted_at IS NULL
ORDER BY bundle_name
LIMIT 3;

-- UNCOMMENT and replace IDs:
/*
-- Set target omzet dan fokus
INSERT INTO user_targets (user_id, period_id, target_omzet, target_fokus_total)
VALUES (
    'USER-ID-FROM-STEP-1',
    'PERIOD-ID-FROM-QUERY-ABOVE',
    50000000,  -- 50 juta
    30         -- 30 unit fokus
);

-- Set fokus per bundle
INSERT INTO fokus_targets (user_id, period_id, bundle_id, target_qty)
VALUES 
    ('USER-ID-FROM-STEP-1', 'PERIOD-ID', 'BUNDLE-ID-1', 15),
    ('USER-ID-FROM-STEP-1', 'PERIOD-ID', 'BUNDLE-ID-2', 15);
*/

/*
STEP 4: Create some dummy sales data for testing
*/
-- UNCOMMENT and replace IDs:
/*
-- Get a variant ID first
SELECT 'Copy a Variant ID:' as note, pv.id, p.model_name, pv.variant_name
FROM product_variants pv
JOIN products p ON pv.product_id = p.id
LIMIT 5;

-- Insert dummy sales
INSERT INTO sales_sell_out (
    promotor_id, 
    variant_id, 
    transaction_date, 
    customer_name,
    customer_phone,
    price_sell,
    imei
)
VALUES 
    ('USER-ID-FROM-STEP-1', 'VARIANT-ID', CURRENT_DATE, 'Customer Test 1', '081111111111', 3500000, '123456789012345'),
    ('USER-ID-FROM-STEP-1', 'VARIANT-ID', CURRENT_DATE - 1, 'Customer Test 2', '081222222222', 3500000, '123456789012346'),
    ('USER-ID-FROM-STEP-1', 'VARIANT-ID', CURRENT_DATE - 2, 'Customer Test 3', '081333333333', 3500000, '123456789012347');
*/

-- ==========================================
-- FINAL: Verify everything
-- ==========================================
/*
SELECT 'User created:' as check;
SELECT id, email, full_name, role FROM users WHERE email = 'test.promotor@vtrack.com';

SELECT 'Targets set:' as check;
SELECT * FROM user_targets WHERE user_id = 'USER-ID-FROM-STEP-1';

SELECT 'Fokus targets:' as check;
SELECT * FROM fokus_targets WHERE user_id = 'USER-ID-FROM-STEP-1';

SELECT 'Sales data:' as check;
SELECT COUNT(*) FROM sales_sell_out WHERE promotor_id = 'USER-ID-FROM-STEP-1';

SELECT 'Dashboard data:' as check;
SELECT * FROM get_target_dashboard('USER-ID-FROM-STEP-1', 'PERIOD-ID');
*/
