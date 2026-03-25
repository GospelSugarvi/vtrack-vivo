-- Migration: 20260124_fokus_bundles_remove_period.sql
-- Remove period dependency from fokus_bundles - bundles are now GLOBAL
-- Once set, bundles apply to all months until changed by admin

-- ==========================================
-- STEP 1: Remove period_id from fokus_bundles
-- ==========================================

-- First, handle potential duplicates (same bundle_name across periods)
-- Keep only the first occurrence of each bundle_name (by created_at)
DELETE FROM fokus_bundles 
WHERE id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY bundle_name ORDER BY created_at ASC) as rn
        FROM fokus_bundles
    ) ranked
    WHERE rn > 1
);

-- Drop the period constraint and column
ALTER TABLE fokus_bundles DROP CONSTRAINT IF EXISTS fokus_bundles_period_id_bundle_name_key;
ALTER TABLE fokus_bundles DROP CONSTRAINT IF EXISTS fokus_bundles_period_id_fkey;

-- Drop the index
DROP INDEX IF EXISTS idx_fokus_bundles_period;

-- Remove period_id column
ALTER TABLE fokus_bundles DROP COLUMN IF EXISTS period_id;

-- Add new unique constraint on bundle_name only
ALTER TABLE fokus_bundles ADD CONSTRAINT fokus_bundles_bundle_name_unique UNIQUE (bundle_name);

-- ==========================================
-- STEP 2: Update fokus_targets - keep period_id but fix bundle reference
-- ==========================================
-- fokus_targets still needs period_id because target qty can be different each month
-- But now bundle_id references global bundles

-- No change needed for fokus_targets structure
-- It already has: period_id, user_id, bundle_id, target_qty

-- ==========================================
-- STEP 3: Verify structure
-- ==========================================
SELECT 'fokus_bundles columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'fokus_bundles';

SELECT 'fokus_targets columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'fokus_targets';

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Fokus bundles are now GLOBAL (no period dependency)!' as status;
SELECT 'Bundles set once, apply to all months until changed' as note;
