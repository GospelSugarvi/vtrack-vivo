-- Migration: 20260119_create_weekly_targets.sql
-- Global weekly target percentage distribution (single configuration for all months)

-- Drop existing table if exists (to recreate with new structure)
DROP TABLE IF EXISTS weekly_targets CASCADE;

CREATE TABLE weekly_targets (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  week_number int NOT NULL UNIQUE CHECK (week_number >= 1 AND week_number <= 5),
  start_day int NOT NULL,
  end_day int NOT NULL,
  percentage int NOT NULL DEFAULT 25 CHECK (percentage >= 0 AND percentage <= 100),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Index
CREATE INDEX idx_weekly_targets_week ON weekly_targets(week_number);

-- RLS
ALTER TABLE weekly_targets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manage weekly targets" ON weekly_targets
FOR ALL USING (true) WITH CHECK (true);

-- Insert default weeks
INSERT INTO weekly_targets (week_number, start_day, end_day, percentage) VALUES
  (1, 1, 7, 25),
  (2, 8, 14, 25),
  (3, 15, 22, 25),
  (4, 23, 31, 25);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_weekly_targets_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS weekly_targets_updated_at ON weekly_targets;
CREATE TRIGGER weekly_targets_updated_at
BEFORE UPDATE ON weekly_targets
FOR EACH ROW
EXECUTE FUNCTION update_weekly_targets_updated_at();
