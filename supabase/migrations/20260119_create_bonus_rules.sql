-- Migration: 20260119_create_bonus_rules.sql
-- Description: Create table for bonus configuration (range-based and flat)

CREATE TABLE IF NOT EXISTS bonus_rules (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  bonus_type text NOT NULL CHECK (bonus_type IN ('range', 'flat')),
  
  -- For range-based bonus
  min_price numeric,
  max_price numeric,
  bonus_official numeric,
  bonus_training numeric,
  
  -- For flat bonus
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  flat_bonus numeric,
  
  -- Metadata
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  -- Constraints
  CONSTRAINT valid_range_bonus CHECK (
    (bonus_type = 'range' AND min_price IS NOT NULL AND bonus_official IS NOT NULL AND bonus_training IS NOT NULL)
    OR (bonus_type = 'flat' AND product_id IS NOT NULL AND flat_bonus IS NOT NULL)
  )
);

-- Index for faster queries
CREATE INDEX idx_bonus_rules_type ON bonus_rules(bonus_type);
CREATE INDEX idx_bonus_rules_product ON bonus_rules(product_id) WHERE bonus_type = 'flat';

-- RLS Policies
ALTER TABLE bonus_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin manage bonus rules" ON bonus_rules
FOR ALL USING (true) WITH CHECK (true);

-- Insert default range-based bonus rules
INSERT INTO bonus_rules (bonus_type, min_price, max_price, bonus_official, bonus_training) VALUES
  ('range', 0, 2000000, 0, 0),
  ('range', 2000000, 4000000, 25000, 22500),
  ('range', 4000000, 6000000, 45000, 40000),
  ('range', 6000000, 999999999, 90000, 80000);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_bonus_rules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER bonus_rules_updated_at
BEFORE UPDATE ON bonus_rules
FOR EACH ROW
EXECUTE FUNCTION update_bonus_rules_updated_at();
