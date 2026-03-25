-- Minimum Stock Settings Tables

-- Default minimal per product series + store grade
CREATE TABLE IF NOT EXISTS min_stock_defaults (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Product category
  series TEXT, -- 'Y-series', 'V-series', 'X-series', null = all
  network_type TEXT, -- '4G', '5G', null = all
  
  -- Store category
  store_grade TEXT, -- 'A', 'B', 'C', null = all
  
  -- Minimum stock
  min_qty INTEGER NOT NULL DEFAULT 3,
  
  -- Priority (higher = more specific, takes precedence)
  priority INTEGER DEFAULT 0,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(series, network_type, store_grade)
);

-- Override per specific toko + product
CREATE TABLE IF NOT EXISTS min_stock_overrides (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id UUID REFERENCES stores(id),
  product_id UUID REFERENCES products(id),
  variant_id UUID REFERENCES product_variants(id), -- null = all variants of product
  
  min_qty INTEGER NOT NULL,
  notes TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(store_id, product_id, variant_id)
);

-- Stored procedure to get effective min stock
CREATE OR REPLACE FUNCTION get_effective_min_stock(
  p_store_id UUID,
  p_product_id UUID,
  p_variant_id UUID DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
  v_min INTEGER := 3; -- Default fallback
  v_store_grade TEXT;
  v_series TEXT;
  v_network_type TEXT;
BEGIN
  -- Check override first
  SELECT min_qty INTO v_min FROM min_stock_overrides
  WHERE store_id = p_store_id 
    AND product_id = p_product_id
    AND (variant_id = p_variant_id OR variant_id IS NULL)
  ORDER BY variant_id DESC NULLS LAST
  LIMIT 1;
  
  IF v_min IS NOT NULL THEN
    RETURN v_min;
  END IF;
  
  -- Get store grade and product info
  SELECT grade INTO v_store_grade FROM stores WHERE id = p_store_id;
  SELECT series, network_type INTO v_series, v_network_type FROM products WHERE id = p_product_id;
  
  -- Check defaults (most specific first)
  SELECT min_qty INTO v_min FROM min_stock_defaults
  WHERE (series = v_series OR series IS NULL)
    AND (network_type = v_network_type OR network_type IS NULL)
    AND (store_grade = v_store_grade OR store_grade IS NULL)
  ORDER BY priority DESC, series DESC NULLS LAST, network_type DESC NULLS LAST, store_grade DESC NULLS LAST
  LIMIT 1;
  
  RETURN COALESCE(v_min, 3);
END;
$$ LANGUAGE plpgsql;

-- View combining stock with min stock for alerts
CREATE OR REPLACE VIEW v_stock_alerts AS
SELECT 
  st.id as store_id,
  st.store_name,
  p.id as product_id,
  p.model_name,
  pv.id as variant_id,
  pv.ram_rom,
  pv.color,
  COALESCE(stock_count.count, 0) as current_stock,
  get_effective_min_stock(st.id, p.id, pv.id) as min_stock,
  CASE 
    WHEN COALESCE(stock_count.count, 0) = 0 THEN 'empty'
    WHEN COALESCE(stock_count.count, 0) < get_effective_min_stock(st.id, p.id, pv.id) THEN 'low'
    ELSE 'ok'
  END as status
FROM stores st
CROSS JOIN products p
CROSS JOIN product_variants pv
LEFT JOIN (
  SELECT store_id, variant_id, COUNT(*) as count
  FROM stok
  WHERE is_sold = false
  GROUP BY store_id, variant_id
) stock_count ON stock_count.store_id = st.id AND stock_count.variant_id = pv.id
WHERE pv.product_id = p.id
  AND pv.active = true
  AND st.deleted_at IS NULL
  AND p.deleted_at IS NULL;

-- RLS
ALTER TABLE min_stock_defaults ENABLE ROW LEVEL SECURITY;
ALTER TABLE min_stock_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin min_stock_defaults" ON min_stock_defaults FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

CREATE POLICY "Admin min_stock_overrides" ON min_stock_overrides FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Seed default values
INSERT INTO min_stock_defaults (series, network_type, store_grade, min_qty, priority) VALUES
  (NULL, NULL, 'A', 5, 1),
  (NULL, NULL, 'B', 3, 1),
  (NULL, NULL, 'C', 2, 1),
  ('Y-series', '5G', 'A', 4, 10),
  ('V-series', '5G', 'A', 3, 10),
  ('X-series', '5G', 'A', 2, 10)
ON CONFLICT DO NOTHING;
