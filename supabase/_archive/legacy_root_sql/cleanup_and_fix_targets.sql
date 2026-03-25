-- Cleanup Duplicate Targets and Add Protection
-- Run this to fix the issue permanently

-- ==========================================
-- STEP 1: Show current duplicates
-- ==========================================
SELECT 
    'BEFORE: Duplicates Found' as status,
    u.full_name,
    tp.period_name,
    COUNT(*) as duplicate_count
FROM user_targets ut
JOIN users u ON u.id = ut.user_id
JOIN target_periods tp ON tp.id = ut.period_id
GROUP BY u.full_name, tp.period_name
HAVING COUNT(*) > 1;

-- ==========================================
-- STEP 2: Delete duplicates (keep first one)
-- ==========================================
WITH duplicates AS (
    SELECT 
        id,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, period_id 
            ORDER BY id
        ) as rn
    FROM user_targets
)
DELETE FROM user_targets
WHERE id IN (
    SELECT id FROM duplicates WHERE rn > 1
);

-- ==========================================
-- STEP 3: Add unique constraint
-- ==========================================
ALTER TABLE user_targets DROP CONSTRAINT IF EXISTS unique_user_period;
ALTER TABLE user_targets
ADD CONSTRAINT unique_user_period UNIQUE (user_id, period_id);

-- ==========================================
-- STEP 4: Verify - should return no rows
-- ==========================================
SELECT 
    'AFTER: Check Duplicates' as status,
    u.full_name,
    tp.period_name,
    COUNT(*) as count
FROM user_targets ut
JOIN users u ON u.id = ut.user_id
JOIN target_periods tp ON tp.id = ut.period_id
GROUP BY u.full_name, tp.period_name
HAVING COUNT(*) > 1;

-- ==========================================
-- SUCCESS
-- ==========================================
SELECT '✅ Cleanup complete!' as status;
SELECT 'Constraint added: One target per user per period' as info;
SELECT 'Double-click will now show error instead of creating duplicate' as note;
