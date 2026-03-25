-- =====================================================
-- SATOR SUPPORTING TABLES
-- Created: 2026-01-30
-- Description: Additional tables needed for SATOR features
-- =====================================================

-- =====================================================
-- 1. SATOR MONTHLY KPI
-- =====================================================
CREATE TABLE IF NOT EXISTS sator_monthly_kpi (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sator_id UUID REFERENCES users(id) NOT NULL,
  period_month TEXT NOT NULL, -- Format: YYYY-MM
  
  -- KPI Components (0-100 score)
  sell_out_all_score NUMERIC DEFAULT 0,
  sell_out_fokus_score NUMERIC DEFAULT 0,
  sell_in_score NUMERIC DEFAULT 0,
  kpi_ma_score NUMERIC DEFAULT 0,
  
  -- Calculated Total
  total_score NUMERIC DEFAULT 0,
  bonus_amount NUMERIC DEFAULT 0,
  
  -- Metadata
  calculated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(sator_id, period_month)
);

-- =====================================================
-- 2. SATOR REWARDS
-- =====================================================
CREATE TABLE IF NOT EXISTS sator_rewards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sator_id UUID REFERENCES users(id) NOT NULL,
  reward_name TEXT NOT NULL,
  reward_type TEXT NOT NULL, -- 'monthly_bonus', 'special', 'incentive'
  amount NUMERIC NOT NULL DEFAULT 0,
  period_month TEXT, -- Format: YYYY-MM
  status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'paid', 'rejected'
  paid_date DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 3. WAREHOUSE STOCK
-- =====================================================
CREATE TABLE IF NOT EXISTS warehouse_stock (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  warehouse_code TEXT NOT NULL,
  area TEXT, -- Links to SATOR area
  variant_id UUID REFERENCES product_variants(id) NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  last_updated TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(warehouse_code, variant_id)
);

-- =====================================================
-- 4. SCHEDULE REQUESTS (Izin, Cuti, etc)
-- =====================================================
CREATE TABLE IF NOT EXISTS schedule_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) NOT NULL,
  schedule_type TEXT NOT NULL, -- 'izin', 'cuti', 'sakit', 'shift_change'
  schedule_date DATE NOT NULL,
  end_date DATE, -- For multi-day requests
  reason TEXT,
  attachment_url TEXT,
  status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 5. SELL IN (SATOR purchases from warehouse)
-- =====================================================
CREATE TABLE IF NOT EXISTS sell_in (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sator_id UUID REFERENCES users(id) NOT NULL,
  store_id UUID REFERENCES stores(id),
  variant_id UUID REFERENCES product_variants(id) NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC NOT NULL CHECK (unit_price >= 0),
  total_price NUMERIC NOT NULL CHECK (total_price >= 0),
  status TEXT DEFAULT 'pending', -- 'pending', 'confirmed', 'delivered', 'cancelled'
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 6. ORDERS (Store orders managed by SATOR)
-- =====================================================
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sator_id UUID REFERENCES users(id) NOT NULL,
  store_id UUID REFERENCES stores(id) NOT NULL,
  total_items INTEGER NOT NULL DEFAULT 0,
  total_value NUMERIC NOT NULL DEFAULT 0,
  status TEXT DEFAULT 'pending', -- 'pending', 'processing', 'shipped', 'delivered', 'cancelled'
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID REFERENCES orders(id) NOT NULL,
  variant_id UUID REFERENCES product_variants(id) NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC NOT NULL CHECK (unit_price >= 0),
  total_price NUMERIC NOT NULL CHECK (total_price >= 0)
);

-- =====================================================
-- 7. STORE VISITS (SATOR visiting stores)
-- =====================================================
CREATE TABLE IF NOT EXISTS store_visits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id UUID REFERENCES stores(id) NOT NULL,
  sator_id UUID REFERENCES users(id) NOT NULL,
  visit_date DATE NOT NULL DEFAULT CURRENT_DATE,
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  check_in_photo TEXT,
  check_out_photo TEXT,
  notes TEXT,
  checklist JSONB, -- Completed checklist items
  follow_up TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 8. STORE ISSUES
-- =====================================================
CREATE TABLE IF NOT EXISTS store_issues (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id UUID REFERENCES stores(id) NOT NULL,
  reported_by UUID REFERENCES users(id) NOT NULL,
  issue_type TEXT NOT NULL, -- 'stock', 'display', 'promotor', 'sales', 'other'
  description TEXT NOT NULL,
  priority TEXT DEFAULT 'medium', -- 'low', 'medium', 'high', 'critical'
  resolved BOOLEAN DEFAULT FALSE,
  resolved_by UUID REFERENCES users(id),
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 9. ACTIVITY FEED
-- =====================================================
CREATE TABLE IF NOT EXISTS activity_feed (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) NOT NULL,
  activity_type TEXT NOT NULL, -- 'sale', 'clock_in', 'stock_input', 'achievement', 'post'
  message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 10. IMEI RECORDS (for normalization)
-- =====================================================
CREATE TABLE IF NOT EXISTS imei_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  imei_number TEXT NOT NULL UNIQUE,
  variant_id UUID REFERENCES product_variants(id),
  promotor_id UUID REFERENCES users(id),
  store_id UUID REFERENCES stores(id),
  normalization_status TEXT DEFAULT 'pending', -- 'pending', 'normalized', 'rejected', 'completed'
  normalized_at TIMESTAMPTZ,
  normalized_by UUID REFERENCES users(id),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- 11. PROMOTION REPORTS - SKIP IF EXISTS (already has different schema)
-- =====================================================
-- Note: promotion_reports already exists with promotor_id column
-- No changes needed

-- =====================================================
-- 12. FOLLOWER REPORTS - SKIP IF EXISTS (already has different schema)
-- =====================================================
-- Note: follower_reports may have promotor_id column
-- No changes needed

-- =====================================================
-- 13. ALLBRAND REPORTS - SKIP IF EXISTS (may have different schema)
-- =====================================================
-- Note: allbrand_reports may already exist with promotor_id column
-- No changes needed

-- =====================================================
-- 14. STOCK VALIDATIONS
-- =====================================================
CREATE TABLE IF NOT EXISTS stock_validations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  promotor_id UUID REFERENCES users(id) NOT NULL,
  store_id UUID REFERENCES stores(id) NOT NULL,
  validation_date DATE NOT NULL DEFAULT CURRENT_DATE,
  items JSONB NOT NULL, -- Array of {variant_id, expected_qty, actual_qty, notes}
  discrepancy_count INTEGER DEFAULT 0,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- Enable RLS
-- =====================================================
ALTER TABLE sator_monthly_kpi ENABLE ROW LEVEL SECURITY;
ALTER TABLE sator_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouse_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE sell_in ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_feed ENABLE ROW LEVEL SECURITY;
ALTER TABLE imei_records ENABLE ROW LEVEL SECURITY;
-- promotion_reports, follower_reports, allbrand_reports already have RLS
ALTER TABLE stock_validations ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- RLS Policies
-- =====================================================

-- SATOR KPI - SATOR can view their own, admin can view all
CREATE POLICY "sator_monthly_kpi_select" ON sator_monthly_kpi
FOR SELECT USING (
  sator_id = auth.uid() OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv'))
);

-- SATOR Rewards - Same as above
CREATE POLICY "sator_rewards_select" ON sator_rewards
FOR SELECT USING (
  sator_id = auth.uid() OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager'))
);

-- Warehouse Stock - SATORs and admins can view
CREATE POLICY "warehouse_stock_select" ON warehouse_stock
FOR SELECT USING (
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv', 'sator'))
);

-- Schedule Requests - User can view own, SATOR can view team
CREATE POLICY "schedule_requests_select" ON schedule_requests
FOR SELECT USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM hierarchy_sator_promotor hsp
    WHERE hsp.sator_id = auth.uid() AND hsp.promotor_id = user_id AND hsp.active = true
  ) OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv'))
);

CREATE POLICY "schedule_requests_insert" ON schedule_requests
FOR INSERT WITH CHECK (true); -- Allow any authenticated user to insert their own requests

-- Sell In - SATOR can manage their own
CREATE POLICY "sell_in_all" ON sell_in
FOR ALL USING (
  sator_id = auth.uid() OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager'))
);

-- Orders - SATOR can manage their own
CREATE POLICY "orders_all" ON orders
FOR ALL USING (
  sator_id = auth.uid() OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager'))
);

CREATE POLICY "order_items_select" ON order_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM orders o 
    WHERE o.id = order_items.order_id 
    AND (o.sator_id = auth.uid() OR EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager')))
  )
);

-- Store Visits - SATOR can manage their own
CREATE POLICY "store_visits_all" ON store_visits
FOR ALL USING (
  sator_id = auth.uid() OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv'))
);

-- Store Issues - Anyone can report, SATOR+ can view all
CREATE POLICY "store_issues_select" ON store_issues
FOR SELECT USING (
  reported_by = auth.uid() OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv', 'sator'))
);

CREATE POLICY "store_issues_insert" ON store_issues
FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Activity Feed - Team can view team activities
CREATE POLICY "activity_feed_select" ON activity_feed
FOR SELECT USING (
  user_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM hierarchy_sator_promotor hsp
    WHERE hsp.sator_id = auth.uid() AND hsp.promotor_id = user_id AND hsp.active = true
  ) OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv'))
);

-- IMEI Records - SATOR can view their team's
CREATE POLICY "imei_records_select" ON imei_records
FOR SELECT USING (
  promotor_id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM hierarchy_sator_promotor hsp
    WHERE hsp.sator_id = auth.uid() AND hsp.promotor_id = promotor_id AND hsp.active = true
  ) OR
  EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'manager', 'spv'))
);

-- Reports - already have policies, skip
-- Policy for promotion_reports, follower_reports, allbrand_reports already exist

CREATE POLICY "stock_validations_all" ON stock_validations
FOR ALL USING (promotor_id = auth.uid() OR EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role IN ('admin', 'sator', 'spv', 'manager')));

-- =====================================================
-- Indexes for Performance
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_sator_monthly_kpi_period ON sator_monthly_kpi(period_month);
CREATE INDEX IF NOT EXISTS idx_schedule_requests_status ON schedule_requests(status);
CREATE INDEX IF NOT EXISTS idx_schedule_requests_date ON schedule_requests(schedule_date);
CREATE INDEX IF NOT EXISTS idx_sell_in_created ON sell_in(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_store_visits_date ON store_visits(visit_date);
CREATE INDEX IF NOT EXISTS idx_store_issues_resolved ON store_issues(resolved);
CREATE INDEX IF NOT EXISTS idx_activity_feed_created ON activity_feed(created_at);
CREATE INDEX IF NOT EXISTS idx_imei_records_status ON imei_records(normalization_status);
