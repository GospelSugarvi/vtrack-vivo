-- Create reward bundles for Special Rewards multi-product targeting

-- Reward bundles (e.g., "Flagship Series" containing X100 + X200 + V40)
CREATE TABLE IF NOT EXISTS reward_bundles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role text NOT NULL CHECK (role IN ('sator', 'spv')),
  bundle_name text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(role, bundle_name)
);

-- Bundle products (many-to-many: bundle -> products)
CREATE TABLE IF NOT EXISTS reward_bundle_products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  bundle_id uuid REFERENCES reward_bundles(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(bundle_id, product_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_reward_bundles_role ON reward_bundles(role);
CREATE INDEX IF NOT EXISTS idx_reward_bundle_products_bundle ON reward_bundle_products(bundle_id);
CREATE INDEX IF NOT EXISTS idx_reward_bundle_products_product ON reward_bundle_products(product_id);

-- Add bundle_id to special_rewards (nullable, either product_id OR bundle_id)
ALTER TABLE special_rewards ADD COLUMN IF NOT EXISTS bundle_id uuid REFERENCES reward_bundles(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_special_rewards_bundle ON special_rewards(bundle_id);

-- RLS
ALTER TABLE reward_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE reward_bundle_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manage reward bundles" ON reward_bundles
FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Admin manage reward bundle products" ON reward_bundle_products
FOR ALL USING (true) WITH CHECK (true);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_reward_bundles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS reward_bundles_updated_at ON reward_bundles;
CREATE TRIGGER reward_bundles_updated_at
BEFORE UPDATE ON reward_bundles
FOR EACH ROW
EXECUTE FUNCTION update_reward_bundles_updated_at();
