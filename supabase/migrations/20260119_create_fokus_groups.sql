-- Migration: 20260119_create_fokus_groups.sql
-- Table for storing which product groups are "fokus" per period
-- Groups are base product names (e.g., "V60 LITE" covers both V60 LITE 4G and V60 LITE 5G)

CREATE TABLE IF NOT EXISTS fokus_groups (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  group_name text NOT NULL, -- e.g., "V60 LITE", "Y400", "Y21D"
  created_at timestamptz DEFAULT now(),
  UNIQUE(period_id, group_name)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_fokus_groups_period ON fokus_groups(period_id);

-- RLS
ALTER TABLE fokus_groups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage fokus groups" ON fokus_groups;
CREATE POLICY "Admin manage fokus groups" ON fokus_groups
FOR ALL USING (true) WITH CHECK (true);
