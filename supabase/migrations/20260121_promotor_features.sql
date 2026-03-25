-- Promotor Role Additional Features
-- Based on: 03_UI_PROMOTOR_ROLE.md

-- ==========================================
-- 1. IMEI NORMALIZATION SYSTEM
-- ==========================================
CREATE TABLE IF NOT EXISTS imei_normalization (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id UUID REFERENCES stores(id),
  promotor_id UUID REFERENCES users(id),
  
  -- Product Info
  imei VARCHAR(255) NOT NULL,
  model_name VARCHAR(255),
  
  -- Status flow: pending -> sending -> normalized -> scanned
  status VARCHAR(20) DEFAULT 'pending', -- pending, sent, normalized, scanned
  
  requested_at TIMESTAMPTZ DEFAULT now(),
  normalized_at TIMESTAMPTZ,
  scanned_at TIMESTAMPTZ,
  
  -- Admin/SATOR who normalized
  normalized_by UUID REFERENCES users(id)
);

-- Index for quick lookup
CREATE INDEX IF NOT EXISTS idx_normalization_status ON imei_normalization(status);
CREATE INDEX IF NOT EXISTS idx_normalization_promotor ON imei_normalization(promotor_id);

-- ==========================================
-- 2. REPORTING TABLES (Non-Stock)
-- ==========================================

-- A. Lapor Promosi (Sosmed)
CREATE TABLE IF NOT EXISTS report_promosi (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  activity_record_id UUID REFERENCES activity_records(id), -- Linked to daily activity
  
  platform VARCHAR(50), -- TikTok, Instagram, Facebook, WhatsApp
  link_url TEXT,
  screenshot_url TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now()
);

-- B. Lapor Follower
CREATE TABLE IF NOT EXISTS report_follower (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  
  platform VARCHAR(50), -- TikTok, Instagram
  username VARCHAR(100),
  follower_count INTEGER,
  screenshot_url TEXT,
  
  report_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Makassar')::DATE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- C. Lapor AllBrand (Kompetitor)
CREATE TABLE IF NOT EXISTS report_allbrand (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  store_id UUID REFERENCES stores(id),
  
  brand VARCHAR(50), -- Oppo, Samsung, Realme, Xiaomi, Infinix
  range_price VARCHAR(50), -- <1jt, 1-2jt, 2-3jt, 3-4jt, >4jt
  quantity INTEGER DEFAULT 0,
  
  report_date DATE DEFAULT (now() AT TIME ZONE 'Asia/Makassar')::DATE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 3. VAST FINANCE
-- ==========================================
CREATE TABLE IF NOT EXISTS report_vast (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  store_id UUID REFERENCES stores(id),
  
  customer_name VARCHAR(100),
  phone_number VARCHAR(20),
  product_model VARCHAR(100),
  
  status VARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected
  notes TEXT,
  
  proof_url TEXT,
  
  submitted_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 4. RLS POLICIES
-- ==========================================
ALTER TABLE imei_normalization ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_promosi ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_follower ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_allbrand ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_vast ENABLE ROW LEVEL SECURITY;

-- Promotor: CRUD own data
CREATE POLICY "Promotor own normalization" ON imei_normalization FOR ALL USING (promotor_id = auth.uid());
CREATE POLICY "Promotor own promo" ON report_promosi FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Promotor own follower" ON report_follower FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Promotor own allbrand" ON report_allbrand FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Promotor own vast" ON report_vast FOR ALL USING (user_id = auth.uid());

-- SATOR/SPV/Admin: View team data
-- (Simplified for now: admin/manager/spv/sator see all, refine later if needed)
CREATE POLICY "Management view normalization" ON imei_normalization FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
);

CREATE POLICY "Management view reports" ON report_promosi FOR SELECT USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
);
-- Repeat for others...
