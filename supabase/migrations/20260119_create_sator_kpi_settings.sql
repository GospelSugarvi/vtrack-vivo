-- Migration: 20260119_create_sator_kpi_settings.sql
-- KPI settings for SATOR/SPV bonus calculation

CREATE TABLE IF NOT EXISTS sator_kpi_settings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  kpi_name text NOT NULL,
  weight int NOT NULL DEFAULT 0, -- percentage weight
  description text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_sator_kpi_weight ON sator_kpi_settings(weight DESC);

-- RLS
ALTER TABLE sator_kpi_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage sator kpi" ON sator_kpi_settings;
CREATE POLICY "Admin manage sator kpi" ON sator_kpi_settings
FOR ALL USING (true) WITH CHECK (true);

-- Trigger
CREATE OR REPLACE FUNCTION update_sator_kpi_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sator_kpi_updated_at ON sator_kpi_settings;
CREATE TRIGGER sator_kpi_updated_at
BEFORE UPDATE ON sator_kpi_settings
FOR EACH ROW
EXECUTE FUNCTION update_sator_kpi_updated_at();
