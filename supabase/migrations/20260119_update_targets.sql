-- Migration: 20260119_update_targets.sql
-- Complete target system with fokus product targets

-- Update user_targets with correct types
ALTER TABLE user_targets ADD COLUMN IF NOT EXISTS target_sell_in BIGINT DEFAULT 0; -- Rupiah
ALTER TABLE user_targets ADD COLUMN IF NOT EXISTS target_sell_out BIGINT DEFAULT 0; -- Rupiah
ALTER TABLE user_targets ADD COLUMN IF NOT EXISTS target_fokus int DEFAULT 0; -- Total fokus (umum)
ALTER TABLE user_targets ADD COLUMN IF NOT EXISTS target_tiktok int DEFAULT 0;
ALTER TABLE user_targets ADD COLUMN IF NOT EXISTS target_follower int DEFAULT 0;
ALTER TABLE user_targets ADD COLUMN IF NOT EXISTS target_vast int DEFAULT 0;

-- Fokus targets per product (detail breakdown)
CREATE TABLE IF NOT EXISTS fokus_targets (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  target_qty int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(period_id, user_id, product_id)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_fokus_targets_period ON fokus_targets(period_id);
CREATE INDEX IF NOT EXISTS idx_fokus_targets_user ON fokus_targets(user_id);

-- RLS
ALTER TABLE fokus_targets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage fokus targets" ON fokus_targets;
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
