-- ============================================
-- JALANKAN FILE INI UNTUK FIX IMEI NORMALIZATION
-- ============================================

-- STEP 1: Buat tabel sator_store_assignments
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

CREATE INDEX IF NOT EXISTS idx_sator_store_assignments_sator 
  ON sator_store_assignments(sator_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_sator_store_assignments_store 
  ON sator_store_assignments(store_id) WHERE is_active = true;

-- STEP 2: RLS
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

-- STEP 3: Auto-assign stores dari IMEI data
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

-- STEP 4: Fix function get_sator_imei_list
DROP FUNCTION IF EXISTS get_sator_imei_list(UUID);

CREATE OR REPLACE FUNCTION get_sator_imei_list(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
BEGIN
  WITH imei_data AS (
    SELECT 
      in2.id,
      in2.imei,
      p.model_name as product_name,
      pv.ram_rom as variant,
      in2.status,
      in2.notes,
      u.full_name as promotor_name,
      s.store_name,
      in2.sold_at,
      in2.created_at,
      in2.updated_at
    FROM imei_normalizations in2
    INNER JOIN users u ON in2.promotor_id = u.id
    INNER JOIN stores s ON in2.store_id = s.id
    LEFT JOIN product_variants pv ON in2.variant_id = pv.id
    LEFT JOIN products p ON pv.product_id = p.id
    WHERE in2.store_id IN (
      SELECT store_id 
      FROM sator_store_assignments 
      WHERE sator_id = p_sator_id 
        AND is_active = true
    )
    ORDER BY in2.created_at DESC
    LIMIT 500
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', id,
      'imei', imei,
      'product_name', product_name,
      'variant', variant,
      'status', status,
      'notes', notes,
      'promotor_name', promotor_name,
      'store_name', store_name,
      'sold_at', sold_at,
      'created_at', created_at,
      'updated_at', updated_at
    )
  ), '[]'::json) INTO result
  FROM imei_data;
  
  RETURN result;
END;
$$;

-- STEP 5: Verify
DO $$
DECLARE
  test_sator_id UUID;
  test_result JSON;
  assignment_count INT;
  imei_count INT;
BEGIN
  SELECT id INTO test_sator_id
  FROM users
  WHERE role = 'sator'
  LIMIT 1;
  
  IF test_sator_id IS NOT NULL THEN
    RAISE NOTICE '=== VERIFICATION ===';
    
    SELECT COUNT(*) INTO assignment_count
    FROM sator_store_assignments
    WHERE sator_id = test_sator_id AND is_active = true;
    RAISE NOTICE '✅ Store assignments: %', assignment_count;
    
    SELECT get_sator_imei_list(test_sator_id) INTO test_result;
    SELECT json_array_length(test_result) INTO imei_count;
    RAISE NOTICE '✅ IMEI records visible: %', imei_count;
    
    IF imei_count > 0 THEN
      RAISE NOTICE '✅ SUCCESS! Data IMEI sudah bisa dilihat Sator';
    ELSE
      RAISE NOTICE '⚠️  No IMEI found, check data';
    END IF;
  END IF;
END $$;
