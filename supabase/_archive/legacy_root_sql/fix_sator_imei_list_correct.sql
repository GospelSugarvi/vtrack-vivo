-- ============================================
-- FIX: get_sator_imei_list Function - CORRECT VERSION
-- Masalah: Function menggunakan kolom 'new_imei' dan 'old_imei' yang tidak ada
-- Solusi: Gunakan kolom 'imei' yang benar sesuai struktur tabel
-- Fix: Gunakan 'store_name' bukan 'name' untuk tabel stores
-- ============================================

-- Drop function lama
DROP FUNCTION IF EXISTS get_sator_imei_list(UUID);

-- Buat function baru dengan kolom yang benar
CREATE OR REPLACE FUNCTION get_sator_imei_list(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
BEGIN
  -- Ambil data dari imei_normalizations berdasarkan store assignment
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', i.id,
      'imei', i.imei,
      'product_name', COALESCE(p.model_name || ' ' || pv.ram_rom || ' ' || pv.color, 'Unknown Product'),
      'status', i.status,
      'promotor_name', u.full_name,
      'store_name', s.store_name,
      'sold_at', i.sold_at,
      'sent_to_sator_at', i.sent_to_sator_at,
      'normalized_at', i.normalized_at,
      'scanned_at', i.scanned_at,
      'notes', i.notes,
      'created_at', i.created_at,
      'updated_at', i.updated_at
    ) ORDER BY i.created_at DESC
  ), '[]'::json) INTO result
  FROM imei_normalizations i
  INNER JOIN users u ON i.promotor_id = u.id
  INNER JOIN stores s ON i.store_id = s.id
  LEFT JOIN product_variants pv ON i.variant_id = pv.id
  LEFT JOIN products p ON i.product_id = p.id
  WHERE i.store_id IN (
    -- Ambil store yang di-assign ke sator ini
    SELECT store_id 
    FROM sator_store_assignments 
    WHERE sator_id = p_sator_id 
      AND is_active = true
  )
  LIMIT 500;
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_sator_imei_list IS 'Get list of IMEI normalization requests for stores assigned to a SATOR';

-- Test function
DO $$
DECLARE
  test_sator_id UUID;
  test_result JSON;
  test_count INT;
BEGIN
  -- Ambil sator pertama untuk test
  SELECT id INTO test_sator_id
  FROM users
  WHERE role = 'sator'
  LIMIT 1;
  
  IF test_sator_id IS NOT NULL THEN
    RAISE NOTICE '=== Testing get_sator_imei_list ===';
    RAISE NOTICE 'Sator ID: %', test_sator_id;
    
    -- Test function
    SELECT get_sator_imei_list(test_sator_id) INTO test_result;
    SELECT json_array_length(test_result) INTO test_count;
    
    RAISE NOTICE 'Result count: %', test_count;
    
    IF test_count > 0 THEN
      RAISE NOTICE 'Sample result: %', (test_result->0)::text;
    ELSE
      RAISE NOTICE 'No IMEI records found. Checking data...';
      
      -- Check if there are any IMEI records
      SELECT COUNT(*) INTO test_count FROM imei_normalizations;
      RAISE NOTICE 'Total IMEI records in table: %', test_count;
      
      -- Check if sator has store assignments
      SELECT COUNT(*) INTO test_count 
      FROM sator_store_assignments 
      WHERE sator_id = test_sator_id AND is_active = true;
      RAISE NOTICE 'Active store assignments for this sator: %', test_count;
    END IF;
  ELSE
    RAISE NOTICE 'No sator found for testing';
  END IF;
END $$;
