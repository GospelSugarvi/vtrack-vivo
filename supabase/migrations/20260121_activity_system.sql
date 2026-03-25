-- Activity Management System

-- ==========================================
-- 1. Activity Types (Admin managed)
-- ==========================================
CREATE TABLE IF NOT EXISTS activity_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  name TEXT NOT NULL,
  description TEXT,
  icon_name TEXT DEFAULT 'check_circle', -- Flutter icon name
  
  -- Settings
  is_active BOOLEAN DEFAULT true,
  is_required BOOLEAN DEFAULT false,
  schedule TEXT DEFAULT 'daily', -- 'morning', 'evening', 'daily', 'on_demand'
  
  -- Target role
  target_role TEXT DEFAULT 'promotor', -- 'promotor', 'sator', 'all'
  
  -- Order for display
  display_order INTEGER DEFAULT 0,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 2. Activity Records (Logged by users)
-- ==========================================
CREATE TABLE IF NOT EXISTS activity_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  user_id UUID REFERENCES users(id) NOT NULL,
  activity_type_id UUID REFERENCES activity_types(id) NOT NULL,
  
  -- Date (WITA)
  activity_date DATE NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Makassar')::DATE,
  
  -- Details
  notes TEXT,
  data JSONB, -- Flexible field for activity-specific data
  proof_url TEXT, -- Image proof if needed
  
  -- Status
  status TEXT DEFAULT 'completed', -- 'completed', 'pending_approval', 'rejected'
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  
  -- One record per user per activity per day
  UNIQUE(user_id, activity_type_id, activity_date)
);

-- ==========================================
-- 3. Clock-in/Clock-out Table
-- ==========================================
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) NOT NULL,
  attendance_date DATE NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Makassar')::DATE,
  
  clock_in TIMESTAMPTZ,
  clock_in_location JSONB, -- {lat, lng, address}
  
  clock_out TIMESTAMPTZ,
  clock_out_location JSONB,
  
  notes TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(user_id, attendance_date)
);

-- ==========================================
-- 4. RLS Policies
-- ==========================================
ALTER TABLE activity_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;

-- Activity types: read for all, manage for admin
CREATE POLICY "Read activity_types" ON activity_types FOR SELECT USING (true);
CREATE POLICY "Admin manage activity_types" ON activity_types FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Activity records: own for user, team for sator/spv, all for admin
CREATE POLICY "Own activity_records" ON activity_records FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Team activity_records" ON activity_records FOR SELECT USING (
  user_id IN (
    SELECT promotor_id FROM hierarchy_sator_promotor WHERE sator_id = auth.uid() AND active = true
  )
);
CREATE POLICY "Admin activity_records" ON activity_records FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv'))
);

-- Attendance same pattern
CREATE POLICY "Own attendance" ON attendance FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Admin attendance" ON attendance FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'manager', 'spv', 'sator'))
);

-- ==========================================
-- 5. Seed Default Activities
-- ==========================================
INSERT INTO activity_types (name, description, icon_name, is_active, is_required, schedule, display_order) VALUES
  ('Clock-in', 'Absensi masuk kerja', 'access_time', true, true, 'morning', 1),
  ('Sell Out', 'Input data penjualan', 'shopping_cart', true, false, 'daily', 2),
  ('Laporan Stok', 'Cek dan laporkan stok', 'inventory', true, true, 'evening', 3),
  ('Promosi/TikTok', 'Upload konten promosi', 'campaign', true, true, 'daily', 4),
  ('VAST Finance', 'Input data cicilan', 'attach_money', true, false, 'on_demand', 5),
  ('AllBrand Report', 'Laporan harian ke AllBrand', 'all_inclusive', true, true, 'evening', 6),
  ('Validasi Stok', 'Validasi stok akhir hari', 'fact_check', true, true, 'evening', 7),
  ('Clock-out', 'Absensi pulang kerja', 'logout', true, true, 'evening', 8)
ON CONFLICT DO NOTHING;

-- ==========================================
-- 6. View for Daily Activity Status
-- ==========================================
CREATE OR REPLACE VIEW v_daily_activity_status AS
SELECT 
  u.id as user_id,
  u.full_name,
  at.id as activity_type_id,
  at.name as activity_name,
  at.is_required,
  (now() AT TIME ZONE 'Asia/Makassar')::DATE as today,
  CASE WHEN ar.id IS NOT NULL THEN true ELSE false END as completed
FROM users u
CROSS JOIN activity_types at
LEFT JOIN activity_records ar ON ar.user_id = u.id 
  AND ar.activity_type_id = at.id 
  AND ar.activity_date = (now() AT TIME ZONE 'Asia/Makassar')::DATE
WHERE u.role = 'promotor' 
  AND u.deleted_at IS NULL
  AND at.is_active = true
  AND at.target_role IN ('promotor', 'all');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_activity_records_user_date ON activity_records(user_id, activity_date);
CREATE INDEX IF NOT EXISTS idx_attendance_user_date ON attendance(user_id, attendance_date);
