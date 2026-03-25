-- Fix Duplicate Targets Issue
-- Prevent double-click from creating duplicate records

-- ==========================================
-- STEP 1: Delete duplicate targets (keep newest)
-- ==========================================
DELETE FROM user_targets
WHERE id IN (
    SELECT id
    FROM (
        SELECT 
            id,
            ROW_NUMBER() OVER (
                PARTITION BY user_id, period_id 
                ORDER BY id DESC
            ) as rn
        FROM user_targets
    ) t
    WHERE rn > 1
);

-- ==========================================
-- STEP 2: Add unique constraint
-- ==========================================
-- Drop old constraint if exists
ALTER TABLE user_targets DROP CONSTRAINT IF EXISTS unique_user_period;

-- Add new constraint: one target per user per period
ALTER TABLE user_targets
ADD CONSTRAINT unique_user_period UNIQUE (user_id, period_id);

-- ==========================================
-- STEP 3: Verify cleanup
-- ==========================================
SELECT 
    'After Cleanup' as status,
    u.full_name,
    tp.period_name,
    COUNT(*) as target_count
FROM user_targets ut
JOIN users u ON u.id = ut.user_id
JOIN target_periods tp ON tp.id = ut.period_id
GROUP BY u.full_name, tp.period_name
HAVING COUNT(*) > 1;

-- If no rows returned, cleanup successful!

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Duplicate targets deleted and constraint added!' as status;
SELECT 'Now double-click will not create duplicates' as info;
