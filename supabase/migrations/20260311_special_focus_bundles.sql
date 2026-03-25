-- Migration: 20260311_special_focus_bundles.sql
-- Special focus bundles per period (tipe khusus)

CREATE TABLE IF NOT EXISTS public.special_focus_bundles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  period_id uuid REFERENCES target_periods(id) ON DELETE CASCADE,
  bundle_name text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(period_id, bundle_name)
);

CREATE TABLE IF NOT EXISTS public.special_focus_bundle_products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  bundle_id uuid REFERENCES special_focus_bundles(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(bundle_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_special_focus_bundles_period
  ON public.special_focus_bundles(period_id);

CREATE INDEX IF NOT EXISTS idx_special_focus_bundle_products_bundle
  ON public.special_focus_bundle_products(bundle_id);

ALTER TABLE public.special_focus_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.special_focus_bundle_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage special focus bundles" ON public.special_focus_bundles;
CREATE POLICY "Admin manage special focus bundles" ON public.special_focus_bundles
FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Admin manage special focus bundle products" ON public.special_focus_bundle_products;
CREATE POLICY "Admin manage special focus bundle products" ON public.special_focus_bundle_products
FOR ALL USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.update_special_focus_bundles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS special_focus_bundles_updated_at ON public.special_focus_bundles;
CREATE TRIGGER special_focus_bundles_updated_at
BEFORE UPDATE ON public.special_focus_bundles
FOR EACH ROW
EXECUTE FUNCTION public.update_special_focus_bundles_updated_at();
