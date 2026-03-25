-- Migration: 20260119_update_fokus_targets.sql
-- Update fokus_targets to use group_name instead of product_id

-- Drop old table if exists (to recreate with new structure)
DROP TABLE IF EXISTS fokus_targets CASCADE;

CREATE TABLE fokus_targets (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  group_name text NOT NULL, -- e.g., "V60 LITE", "Y400"
  target_qty int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(period_id, user_id, group_name)
);

-- Index
CREATE INDEX idx_fokus_targets_period ON fokus_targets(period_id);
CREATE INDEX idx_fokus_targets_user ON fokus_targets(user_id);
CREATE INDEX idx_fokus_targets_group ON fokus_targets(group_name);

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

CREATE TRIGGER fokus_targets_updated_at
BEFORE UPDATE ON fokus_targets
FOR EACH ROW
EXECUTE FUNCTION update_fokus_targets_updated_at();
