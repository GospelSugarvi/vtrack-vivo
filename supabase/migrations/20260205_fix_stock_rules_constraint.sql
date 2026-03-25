-- ==========================================================
-- FIX: Add unique constraint to stock_rules (v2)
-- ==========================================================

-- Cara lain: Recreate table
DROP TABLE IF EXISTS stock_rules;

CREATE TABLE stock_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  grade TEXT NOT NULL,
  product_id UUID NOT NULL REFERENCES products(id),
  min_qty INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(grade, product_id)
);

-- Enable RLS
ALTER TABLE stock_rules ENABLE ROW LEVEL SECURITY;

-- Policy
CREATE POLICY "Anyone can read stock_rules" ON stock_rules FOR SELECT USING (true);
CREATE POLICY "Anyone can insert stock_rules" ON stock_rules FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update stock_rules" ON stock_rules FOR UPDATE USING (true);
