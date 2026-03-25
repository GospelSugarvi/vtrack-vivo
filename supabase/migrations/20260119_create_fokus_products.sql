-- Migration: 20260119_create_fokus_products.sql
-- Table for storing which products are "fokus" per period

CREATE TABLE IF NOT EXISTS fokus_products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(period_id, product_id)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_fokus_products_period ON fokus_products(period_id);

-- RLS
ALTER TABLE fokus_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage fokus products" ON fokus_products;
CREATE POLICY "Admin manage fokus products" ON fokus_products
FOR ALL USING (true) WITH CHECK (true);
