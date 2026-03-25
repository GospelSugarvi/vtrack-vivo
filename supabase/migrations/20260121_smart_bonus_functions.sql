-- Smart Bonus System - Calculation Functions
-- Menghubungkan KPI settings dengan data aktual

-- ==========================================
-- 1. KPI MA Manual Scores Table
-- ==========================================
CREATE TABLE IF NOT EXISTS kpi_ma_scores (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sator_id UUID REFERENCES users(id) NOT NULL,
  period_date DATE NOT NULL, -- First day of month
  score DECIMAL(5,2) CHECK (score >= 0 AND score <= 100),
  notes TEXT,
  created_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(sator_id, period_date)
);

-- ==========================================
-- 2. Calculate Sell Out Total for SATOR's team
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_sator_sellout(
  p_sator_id UUID,
  p_start_date DATE,
  p_end_date DATE
) RETURNS TABLE(
  total_units BIGINT,
  total_omzet NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(COUNT(*), 0)::BIGINT as total_units,
    COALESCE(SUM(s.price_at_transaction), 0) as total_omzet
  FROM sales_sell_out s
  JOIN hierarchy_sator_promotor h ON s.promotor_id = h.promotor_id
  WHERE h.sator_id = p_sator_id
    AND h.active = true
    AND s.transaction_date BETWEEN p_start_date AND p_end_date
    AND s.deleted_at IS NULL
    AND s.status = 'approved';
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 3. Calculate Sell In Total for SATOR
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_sator_sellin(
  p_sator_id UUID,
  p_start_date DATE,
  p_end_date DATE
) RETURNS TABLE(
  total_units BIGINT,
  total_value NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(SUM(qty), 0)::BIGINT as total_units,
    COALESCE(SUM(total_value), 0) as total_value
  FROM sales_sell_in
  WHERE sator_id = p_sator_id
    AND transaction_date BETWEEN p_start_date AND p_end_date
    AND deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 4. Calculate Fokus Product Sell Out
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_sator_fokus(
  p_sator_id UUID,
  p_start_date DATE,
  p_end_date DATE
) RETURNS TABLE(
  total_units BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(COUNT(*), 0)::BIGINT as total_units
  FROM sales_sell_out s
  JOIN hierarchy_sator_promotor h ON s.promotor_id = h.promotor_id
  JOIN product_variants pv ON s.variant_id = pv.id
  JOIN products p ON pv.product_id = p.id
  WHERE h.sator_id = p_sator_id
    AND h.active = true
    AND s.transaction_date BETWEEN p_start_date AND p_end_date
    AND s.deleted_at IS NULL
    AND s.status = 'approved'
    AND p.is_focus = true;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 5. Calculate Fokus Bundle Achievement
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_sator_bundle_fokus(
  p_sator_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_bundle_id UUID
) RETURNS TABLE(
  total_units BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(COUNT(*), 0)::BIGINT as total_units
  FROM sales_sell_out s
  JOIN hierarchy_sator_promotor h ON s.promotor_id = h.promotor_id
  JOIN product_variants pv ON s.variant_id = pv.id
  JOIN fokus_bundle_products fbp ON pv.product_id = fbp.product_id
  WHERE h.sator_id = p_sator_id
    AND h.active = true
    AND fbp.bundle_id = p_bundle_id
    AND s.transaction_date BETWEEN p_start_date AND p_end_date
    AND s.deleted_at IS NULL
    AND s.status = 'approved';
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 6. Get KPI MA Score
-- ==========================================
CREATE OR REPLACE FUNCTION get_sator_kpi_ma(
  p_sator_id UUID,
  p_period_date DATE
) RETURNS DECIMAL AS $$
DECLARE
  v_score DECIMAL;
BEGIN
  SELECT score INTO v_score
  FROM kpi_ma_scores
  WHERE sator_id = p_sator_id
    AND period_date = date_trunc('month', p_period_date)::DATE;
  
  RETURN COALESCE(v_score, 0);
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 7. Calculate Complete SATOR KPI Score
-- ==========================================
CREATE OR REPLACE FUNCTION calculate_sator_kpi(
  p_sator_id UUID,
  p_period_date DATE
) RETURNS TABLE(
  kpi_name TEXT,
  weight INTEGER,
  achievement DECIMAL,
  weighted_score DECIMAL
) AS $$
DECLARE
  v_start_date DATE;
  v_end_date DATE;
  v_sellout_units BIGINT;
  v_sellin_units BIGINT;
  v_fokus_units BIGINT;
  v_ma_score DECIMAL;
  v_target RECORD;
BEGIN
  -- Get period dates
  v_start_date := date_trunc('month', p_period_date)::DATE;
  v_end_date := (date_trunc('month', p_period_date) + interval '1 month' - interval '1 day')::DATE;
  
  -- Get actual data
  SELECT * INTO v_target FROM calculate_sator_sellout(p_sator_id, v_start_date, v_end_date);
  v_sellout_units := v_target.total_units;
  
  SELECT * INTO v_target FROM calculate_sator_sellin(p_sator_id, v_start_date, v_end_date);
  v_sellin_units := v_target.total_units;
  
  SELECT * INTO v_target FROM calculate_sator_fokus(p_sator_id, v_start_date, v_end_date);
  v_fokus_units := v_target.total_units;
  
  v_ma_score := get_sator_kpi_ma(p_sator_id, p_period_date);
  
  -- Return KPI breakdown based on settings
  RETURN QUERY
  SELECT 
    k.kpi_name,
    k.weight,
    CASE k.kpi_name
      WHEN 'Sell Out' THEN v_sellout_units::DECIMAL
      WHEN 'Sell In' THEN v_sellin_units::DECIMAL
      WHEN 'Fokus Produk' THEN v_fokus_units::DECIMAL
      WHEN 'KPI MA' THEN v_ma_score
      ELSE 0
    END as achievement,
    (k.weight * CASE k.kpi_name
      WHEN 'KPI MA' THEN v_ma_score / 100
      ELSE 0 -- Percentage needs target comparison
    END / 100)::DECIMAL as weighted_score
  FROM kpi_settings k
  WHERE k.role = 'sator'
    AND k.weight > 0;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 8. Indexes for Performance
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_kpi_ma_sator_period ON kpi_ma_scores(sator_id, period_date);
CREATE INDEX IF NOT EXISTS idx_sellin_sator_date ON sales_sell_in(sator_id, transaction_date);
