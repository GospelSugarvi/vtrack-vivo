-- Migration: 20260119_create_fokus_bundles.sql
-- Create fokus bundles for multi-select product targeting

-- Drop old tables
DROP TABLE IF EXISTS fokus_groups CASCADE;
DROP TABLE IF EXISTS fokus_targets CASCADE;

-- Fokus bundles (e.g., "Entry Level" containing Y21D + Y29)
CREATE TABLE fokus_bundles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  bundle_name text NOT NULL, -- e.g., "Y21D/Y29", "V60 Series"
  product_types text[] NOT NULL, -- array of product base names, e.g., ["Y21D", "Y29"]
  created_at timestamptz DEFAULT now(),
  UNIQUE(period_id, bundle_name)
);

-- Index
CREATE INDEX idx_fokus_bundles_period ON fokus_bundles(period_id);

-- RLS
ALTER TABLE fokus_bundles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manage fokus bundles" ON fokus_bundles
FOR ALL USING (true) WITH CHECK (true);

-- Fokus targets per bundle per user
CREATE TABLE fokus_targets (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  bundle_id uuid REFERENCES fokus_bundles(id) ON DELETE CASCADE,
  target_qty int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(period_id, user_id, bundle_id)
);

-- Index
CREATE INDEX idx_fokus_targets_period ON fokus_targets(period_id);
CREATE INDEX idx_fokus_targets_user ON fokus_targets(user_id);
CREATE INDEX idx_fokus_targets_bundle ON fokus_targets(bundle_id);

-- RLS
ALTER TABLE fokus_targets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manage fokus targets" ON fokus_targets
FOR ALL USING (true) WITH CHECK (true);

-- Trigger
CREATE OR REPLACE FUNCTION update_fokus_targets_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS fokus_targets_updated_at ON fokus_targets;
CREATE TRIGGER fokus_targets_updated_at
BEFORE UPDATE ON fokus_targets
FOR EACH ROW
EXECUTE FUNCTION update_fokus_targets_updated_at();
