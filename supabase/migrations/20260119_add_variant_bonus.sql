-- Add ram/storage columns to bonus_rules (simpler than variant_id)

-- 1. Add columns for variant specification without color
ALTER TABLE bonus_rules ADD COLUMN IF NOT EXISTS ram int;
ALTER TABLE bonus_rules ADD COLUMN IF NOT EXISTS storage int;

-- Note: 
-- - If ram/storage are NULL = applies to ALL variants of product
-- - If ram/storage are set = applies only to that specific variant (all colors)
