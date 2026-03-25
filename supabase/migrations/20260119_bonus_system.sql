-- Migration: 20260119_bonus_system.sql
-- Complete bonus system tables

-- 1. Add promotor_status to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS promotor_status text 
  CHECK (promotor_status IN ('official', 'training'));

-- 2. Update bonus_rules table
ALTER TABLE bonus_rules ADD COLUMN IF NOT EXISTS bonus_official int DEFAULT 0;
ALTER TABLE bonus_rules ADD COLUMN IF NOT EXISTS bonus_training int DEFAULT 0;
ALTER TABLE bonus_rules ADD COLUMN IF NOT EXISTS ratio_value int DEFAULT 2;

-- 3. Point ranges for Sator/SPV
CREATE TABLE IF NOT EXISTS point_ranges (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role text NOT NULL CHECK (role IN ('sator', 'spv')),
  min_price bigint NOT NULL DEFAULT 0,
  max_price bigint NOT NULL DEFAULT 0,
  points_per_unit numeric(10,2) NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_point_ranges_role ON point_ranges(role);

ALTER TABLE point_ranges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage point ranges" ON point_ranges;
CREATE POLICY "Admin manage point ranges" ON point_ranges FOR ALL USING (true) WITH CHECK (true);

-- 4. Special rewards for Sator/SPV
CREATE TABLE IF NOT EXISTS special_rewards (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role text NOT NULL CHECK (role IN ('sator', 'spv')),
  product_name text NOT NULL,
  min_unit int NOT NULL DEFAULT 0,
  max_unit int, -- null means unlimited
  reward_amount int NOT NULL DEFAULT 0,
  penalty_threshold int DEFAULT 80, -- % below this = penalty
  penalty_amount int DEFAULT 100000,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_special_rewards_role ON special_rewards(role);

ALTER TABLE special_rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage special rewards" ON special_rewards;
CREATE POLICY "Admin manage special rewards" ON special_rewards FOR ALL USING (true) WITH CHECK (true);

-- 5. KPI settings (update existing or create)
CREATE TABLE IF NOT EXISTS kpi_settings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role text NOT NULL CHECK (role IN ('sator', 'spv')),
  kpi_name text NOT NULL,
  weight int NOT NULL DEFAULT 0,
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_kpi_settings_role ON kpi_settings(role);

ALTER TABLE kpi_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage kpi settings" ON kpi_settings;
CREATE POLICY "Admin manage kpi settings" ON kpi_settings FOR ALL USING (true) WITH CHECK (true);
