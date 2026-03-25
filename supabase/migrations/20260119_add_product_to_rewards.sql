-- Add product_id to special_rewards table

ALTER TABLE special_rewards ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES products(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_special_rewards_product ON special_rewards(product_id);

-- Note: product_name can be removed later, but keep for backward compatibility
-- New entries should use product_id, display will join with products table
