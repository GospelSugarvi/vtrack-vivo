-- Fix: Allow product_name to be NULL when using bundle

ALTER TABLE special_rewards ALTER COLUMN product_name DROP NOT NULL;

-- Add comment for clarity
COMMENT ON COLUMN special_rewards.product_name IS 'Legacy column. Use product_id or bundle_id instead. NULL if using product_id or bundle_id.';
