-- Migration: 20260119_create_kpi_settings.sql
-- KPI settings for SATOR and SPV bonus calculation (separate per role)

DROP TABLE IF EXISTS sator_kpi_settings CASCADE;

CREATE TABLE IF NOT EXISTS kpi_settings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role text NOT NULL CHECK (role IN ('sator', 'spv')),
  kpi_name text NOT NULL,
  weight int NOT NULL DEFAULT 0, -- percentage weight
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_kpi_settings_role ON kpi_settings(role);

-- RLS
ALTER TABLE kpi_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage kpi settings" ON kpi_settings;
CREATE POLICY "Admin manage kpi settings" ON kpi_settings
FOR ALL USING (true) WITH CHECK (true);

-- Trigger
CREATE OR REPLACE FUNCTION update_kpi_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS kpi_settings_updated_at ON kpi_settings;
CREATE TRIGGER kpi_settings_updated_at
BEFORE UPDATE ON kpi_settings
FOR EACH ROW
EXECUTE FUNCTION update_kpi_settings_updated_at();
