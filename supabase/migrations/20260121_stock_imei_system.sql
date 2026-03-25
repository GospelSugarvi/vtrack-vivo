-- IMEI-Based Stock System
-- Per dokumentasi: STOCK_ORDER_COMPLETE_FLOW.md dan STOCK_CONDITION_RULES.md

-- ==========================================
-- 1. MAIN STOCK TABLE (Per IMEI)
-- ==========================================
CREATE TABLE IF NOT EXISTS stok (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Product & Location
  product_id UUID REFERENCES products(id),
  variant_id UUID REFERENCES product_variants(id),
  store_id UUID REFERENCES stores(id),
  promotor_id UUID REFERENCES users(id), -- Current holder
  
  -- IMEI Tracking (CRITICAL!)
  imei VARCHAR(255) UNIQUE NOT NULL,
  
  -- Stock Condition: 'fresh', 'chip', 'display'
  tipe_stok VARCHAR(20) NOT NULL DEFAULT 'fresh',
  
  -- Bonus Tracking (Prevent Double Pay!)
  bonus_paid BOOLEAN DEFAULT false,
  bonus_amount NUMERIC DEFAULT 0,
  bonus_paid_at TIMESTAMPTZ,
  bonus_paid_to UUID REFERENCES users(id),
  
  -- Chip Details (if applicable)
  chip_reason TEXT,
  chip_approved_by UUID REFERENCES users(id),
  chip_approved_at TIMESTAMPTZ,
  
  -- Sale Status
  is_sold BOOLEAN DEFAULT false,
  sold_at TIMESTAMPTZ,
  sold_price NUMERIC,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT check_tipe_stok CHECK (tipe_stok IN ('fresh', 'chip', 'display'))
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_stok_store ON stok(store_id);
CREATE INDEX IF NOT EXISTS idx_stok_product ON stok(product_id);
CREATE INDEX IF NOT EXISTS idx_stok_variant ON stok(variant_id);
CREATE INDEX IF NOT EXISTS idx_stok_imei ON stok(imei);
CREATE INDEX IF NOT EXISTS idx_stok_tipe ON stok(tipe_stok);
CREATE INDEX IF NOT EXISTS idx_stok_unsold ON stok(is_sold) WHERE is_sold = false;
CREATE INDEX IF NOT EXISTS idx_stok_promotor ON stok(promotor_id);

-- ==========================================
-- 2. GUDANG STOCK (SATOR Daily Input)
-- ==========================================
CREATE TABLE IF NOT EXISTS stok_gudang_harian (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES products(id),
  variant_id UUID REFERENCES product_variants(id),
  tanggal DATE NOT NULL,
  
  -- Stock counts
  stok_gudang INTEGER NOT NULL DEFAULT 0,
  stok_otw INTEGER DEFAULT 0, -- On the way
  
  -- Status (auto-calculated)
  status VARCHAR(20), -- 'kosong', 'tipis', 'cukup'
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES users(id),
  
  UNIQUE(product_id, variant_id, tanggal)
);

-- ==========================================
-- 3. TRANSFER REQUEST SYSTEM
-- ==========================================
CREATE TABLE IF NOT EXISTS stock_transfer_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Request Details
  request_type VARCHAR(20) DEFAULT 'request', -- 'request' or 'direct'
  status VARCHAR(20) DEFAULT 'pending', -- pending/approved/rejected/received/cancelled
  
  -- Parties
  from_store_id UUID REFERENCES stores(id),
  to_store_id UUID REFERENCES stores(id),
  requested_by UUID REFERENCES users(id), -- Promotor A
  approved_by UUID REFERENCES users(id),  -- Promotor B
  
  -- Product
  product_id UUID REFERENCES products(id),
  variant_id UUID REFERENCES product_variants(id),
  qty_requested INTEGER NOT NULL,
  qty_approved INTEGER,
  
  -- Reason
  reason TEXT,
  reject_reason TEXT,
  
  -- Timestamps
  requested_at TIMESTAMPTZ DEFAULT now(),
  approved_at TIMESTAMPTZ,
  received_at TIMESTAMPTZ,
  
  CONSTRAINT check_different_store CHECK (from_store_id != to_store_id),
  CONSTRAINT check_request_type CHECK (request_type IN ('request', 'direct')),
  CONSTRAINT check_status CHECK (status IN ('pending', 'approved', 'rejected', 'received', 'cancelled'))
);

-- ==========================================
-- 4. TRANSFER ITEMS (IMEI Level)
-- ==========================================
CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  transfer_request_id UUID REFERENCES stock_transfer_requests(id),
  
  -- IMEI
  stok_id UUID REFERENCES stok(id),
  imei VARCHAR(255) NOT NULL,
  
  -- Status
  is_received BOOLEAN DEFAULT false,
  received_at TIMESTAMPTZ,
  
  -- Note
  condition_note TEXT
);

-- ==========================================
-- 5. STOCK MOVEMENT LOG (Audit Trail)
-- ==========================================
CREATE TABLE IF NOT EXISTS stock_movement_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- IMEI
  stok_id UUID REFERENCES stok(id),
  imei VARCHAR(255) NOT NULL,
  
  -- Movement
  from_store_id UUID REFERENCES stores(id),
  to_store_id UUID REFERENCES stores(id),
  transfer_request_id UUID REFERENCES stock_transfer_requests(id),
  
  -- Type: 'initial', 'transfer_in', 'transfer_out', 'sold', 'chip', 'adjustment'
  movement_type VARCHAR(20) NOT NULL,
  
  -- Actor
  moved_by UUID REFERENCES users(id),
  
  -- Timestamp
  moved_at TIMESTAMPTZ DEFAULT now(),
  
  -- Note
  note TEXT
);

CREATE INDEX IF NOT EXISTS idx_movement_imei ON stock_movement_log(imei);
CREATE INDEX IF NOT EXISTS idx_movement_stok ON stock_movement_log(stok_id);
CREATE INDEX IF NOT EXISTS idx_movement_date ON stock_movement_log(moved_at);

-- ==========================================
-- 6. STORE GROUPS (SPC - Multi-branch)
-- ==========================================
CREATE TABLE IF NOT EXISTS store_groups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_name VARCHAR(255) NOT NULL,
  is_spc BOOLEAN DEFAULT true, -- SPC = multi-branch store
  owner_name VARCHAR(255),
  contact_info TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add group_id to stores if not exists
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='group_id') THEN
    ALTER TABLE stores ADD COLUMN group_id UUID REFERENCES store_groups(id);
  END IF;
END $$;

-- ==========================================
-- 7. DAILY STOCK SNAPSHOT (Historical)
-- ==========================================
CREATE TABLE IF NOT EXISTS stock_daily_snapshot (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  store_id UUID REFERENCES stores(id),
  tanggal DATE NOT NULL,
  
  -- Counts per condition
  fresh_count INTEGER DEFAULT 0,
  chip_count INTEGER DEFAULT 0,
  display_count INTEGER DEFAULT 0,
  total_count INTEGER DEFAULT 0,
  
  -- Value
  total_value NUMERIC,
  
  -- Capture time
  captured_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(store_id, tanggal)
);

-- ==========================================
-- 8. VIEW: Stock per Store (Aggregate)
-- ==========================================
CREATE OR REPLACE VIEW v_stok_toko AS
SELECT 
  s.store_id,
  s.product_id,
  s.variant_id,
  p.model_name,
  pv.ram_rom,
  pv.color,
  COUNT(*) FILTER (WHERE s.tipe_stok = 'fresh' AND s.is_sold = false) as fresh_count,
  COUNT(*) FILTER (WHERE s.tipe_stok = 'chip' AND s.is_sold = false) as chip_count,
  COUNT(*) FILTER (WHERE s.tipe_stok = 'display' AND s.is_sold = false) as display_count,
  COUNT(*) FILTER (WHERE s.is_sold = false) as total_available
FROM stok s
JOIN products p ON s.product_id = p.id
JOIN product_variants pv ON s.variant_id = pv.id
WHERE s.is_sold = false
GROUP BY s.store_id, s.product_id, s.variant_id, p.model_name, pv.ram_rom, pv.color;

-- ==========================================
-- 9. RLS POLICIES
-- ==========================================
ALTER TABLE stok ENABLE ROW LEVEL SECURITY;
ALTER TABLE stok_gudang_harian ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfer_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movement_log ENABLE ROW LEVEL SECURITY;

-- Admin full access
CREATE POLICY "Admin stok" ON stok FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

CREATE POLICY "Admin gudang" ON stok_gudang_harian FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

CREATE POLICY "Admin transfer" ON stock_transfer_requests FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Promotor can see/manage own store's stock
CREATE POLICY "Promotor own stock" ON stok FOR ALL USING (
  promotor_id = auth.uid() OR
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
);

-- SATOR can see team's stock
CREATE POLICY "SATOR team stock" ON stok FOR SELECT USING (
  store_id IN (
    SELECT aps.store_id FROM assignments_promotor_store aps
    JOIN hierarchy_sator_promotor hsp ON aps.promotor_id = hsp.promotor_id
    WHERE hsp.sator_id = auth.uid() AND hsp.active = true AND aps.active = true
  )
);

-- SATOR can manage gudang
CREATE POLICY "SATOR gudang" ON stok_gudang_harian FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'sator'))
);

-- Transfer: involved parties
CREATE POLICY "Transfer parties" ON stock_transfer_requests FOR ALL USING (
  requested_by = auth.uid() OR approved_by = auth.uid() OR
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
);
