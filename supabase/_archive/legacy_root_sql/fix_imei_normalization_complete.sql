-- ============================================
-- FIX COMPLETE: IMEI Normalization untuk Sator
-- Masalah: 
-- 1. Tabel sator_store_assignments belum ada
-- 2. Function get_sator_imei_list menggunakan tabel salah
-- 3. Nama kolom stores salah (name vs store_name)
-- ============================================

-- STEP 1: Cek struktur tabel stores
DO $$
DECLARE
  store_name_col TEXT;
BEGIN
  SELECT column_name INTO store_name_col
  FROM information_schema.columns
  WHERE table_name = 'stores' 
    AND column_name IN ('name', 'store_name')
  LIMIT 1;
  
  RAISE NOTICE 'Stores table uses column: %', store_name_col;
END $$;

-- STEP 2: Buat tabel sator_store_assignments jika belum ada
CREATE TABLE IF NOT EXISTS sator_store_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  is_active BOOLEAN DEFAULT true,
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  assigned_by UUID REFERENCES users(id),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(sator_id, store_id)
);

-- Index untuk performance
CREATE INDEX IF NOT EXISTS idx_sator_store_assignments_sator 
  ON sator_store_assignments(sator_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_sator_store_assignments_store 
  ON sator_store_assignments(store_id) WHERE is_active = true;

-- STEP 3: RLS untuk sator_store_assignments
ALTER TABLE sator_store_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Sator can view their store assignments" ON sator_store_assignments;
CREATE POLICY "Sator can view their store assignments" ON sator_store_assignments
  FOR SELECT USING (
    auth.uid() = sator_id OR
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'spv'))
  );

DROP POLICY IF EXISTS "Admin can manage store assignments" ON sator_store_assignments;
CREATE POLICY "Admin can manage store assignments" ON sator_store_assignments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

-- STEP 4: Auto-assign stores ke sator berdasarkan data yang ada
-- Ambil dari imei_normalizations untuk lihat store mana yang punya data
INSERT INTO sator_store_assignments (sator_id, store_id, is_active, notes)
SELECT DISTINCT 
  hsp.sator_id,
  in2.store_id,
  true,
  'Auto-assigned from IMEI data'
FROM imei_normalizations in2
INNER JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = in2.promotor_id
WHERE hsp.active = true
  AND NOT EXISTS (
    SELECT 1 FROM sator_store_assignments ssa
    WHERE ssa.sator_id = hsp.sator_id 
      AND ssa.store_id = in2.store_id
  )
ON CONFLICT (sator_id, store_id) DO NOTHING;

-- Log hasil
DO $$
DECLARE
  inserted_count INT;
BEGIN
  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RAISE NOTICE 'Auto-assigned % store assignments', inserted_count;
END $$;

-- STEP 5: Drop dan recreate function get_sator_imei_list dengan benar
DROP FUNCTION IF EXISTS get_sator_imei_list(UUID);

CREATE OR REPLACE FUNCTION get_sator_imei_list(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  store_name_column TEXT;
BEGIN
  -- Deteksi nama kolom yang benar untuk stores
  SELECT column_name INTO store_name_column
  FROM information_schema.columns
  WHERE table_name = 'stores' 
    AND column_name IN ('name', 'store_name')
  LIMIT 1;
  
  -- Jika menggunakan 'store_name'
  IF store_name_column = 'store_name' THEN
    SELECT COALESCE(json_agg(
      json_build_object(
        'id', in2.id,
        'imei', in2.new_imei,
        'old_imei', in2.old_imei,
        'product_name', COALESCE(pv.model_name, in2.product_name),
        'status', in2.status,
        'reason', in2.reason,
        'promotor_name', u.full_name,
        'store_name', s.store_name,
        'created_at', in2.created_at,
        'updated_at', in2.updated_at
      ) ORDER BY in2.created_at DESC
    ), '[]'::json) INTO result
    FROM imei_normalizations in2
    INNER JOIN users u ON in2.promotor_id = u.id
    INNER JOIN stores s ON in2.store_id = s.id
    LEFT JOIN product_variants pv ON in2.variant_id = pv.id
    WHERE in2.store_id IN (
      SELECT store_id 
      FROM sator_store_assignments 
      WHERE sator_id = p_sator_id 
        AND is_active = true
    )
    ORDER BY in2.created_at DESC
    LIMIT 500;
  ELSE
    -- Jika menggunakan 'name'
    SELECT COALESCE(json_agg(
      json_build_object(
        'id', in2.id,
        'imei', in2.new_imei,
        'old_imei', in2.old_imei,
        'product_name', COALESCE(pv.model_name, in2.product_name),
        'status', in2.status,
        'reason', in2.reason,
        'promotor_name', u.full_name,
        'store_name', s.name,
        'created_at', in2.created_at,
        'updated_at', in2.updated_at
      ) ORDER BY in2.created_at DESC
    ), '[]'::json) INTO result
    FROM imei_normalizations in2
    INNER JOIN users u ON in2.promotor_id = u.id
    INNER JOIN stores s ON in2.store_id = s.id
    LEFT JOIN product_variants pv ON in2.variant_id = pv.id
    WHERE in2.store_id IN (
      SELECT store_id 
      FROM sator_store_assignments 
      WHERE sator_id = p_sator_id 
        AND is_active = true
    )
    ORDER BY in2.created_at DESC
    LIMIT 500;
  END IF;
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_sator_imei_list IS 'Get list of IMEI normalization requests for stores assigned to a SATOR';

-- STEP 6: Verifikasi hasil
DO $$
DECLARE
  test_sator_id UUID;
  test_result JSON;
  assignment_count INT;
BEGIN
  -- Ambil sator pertama
  SELECT id INTO test_sator_id
  FROM users
  WHERE role = 'sator'
  LIMIT 1;
  
  IF test_sator_id IS NOT NULL THEN
    RAISE NOTICE '=== VERIFICATION ===';
    RAISE NOTICE 'Testing with Sator ID: %', test_sator_id;
    
    -- Cek store assignments
    SELECT COUNT(*) INTO assignment_count
    FROM sator_store_assignments
    WHERE sator_id = test_sator_id AND is_active = true;
    
    RAISE NOTICE 'Store assignments: %', assignment_count;
    
    -- Test function
    SELECT get_sator_imei_list(test_sator_id) INTO test_result;
    
    RAISE NOTICE 'IMEI records found: %', json_array_length(test_result);
    
    IF json_array_length(test_result) > 0 THEN
      RAISE NOTICE 'Sample: %', (test_result->0)::text;
    ELSE
      RAISE NOTICE 'No IMEI records found. Checking data...';
      
      -- Debug: cek imei_normalizations
      RAISE NOTICE 'Total IMEI normalizations: %', (
        SELECT COUNT(*) FROM imei_normalizations
      );
      
      -- Debug: cek stores yang ada IMEI
      RAISE NOTICE 'Stores with IMEI data: %', (
        SELECT STRING_AGG(DISTINCT s.id::text, ', ')
        FROM imei_normalizations in2
        JOIN stores s ON s.id = in2.store_id
      );
    END IF;
  ELSE
    RAISE NOTICE 'No sator found for testing';
  END IF;
END $$;
