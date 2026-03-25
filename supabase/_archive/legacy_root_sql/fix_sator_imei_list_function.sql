-- ============================================
-- FIX: get_sator_imei_list Function
-- Masalah: Function menggunakan tabel 'imei_records' yang salah
-- Solusi: Ganti ke tabel 'imei_normalizations' yang benar
-- ============================================

-- Drop function lama
DROP FUNCTION IF EXISTS get_sator_imei_list(UUID);

-- Buat function baru dengan tabel yang benar
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
BEGIN
  -- Ambil sator pertama untuk test
  SELECT id INTO test_sator_id
  FROM users
  WHERE role = 'sator'
  LIMIT 1;
  
  IF test_sator_id IS NOT NULL THEN
    RAISE NOTICE 'Testing get_sator_imei_list with Sator ID: %', test_sator_id;
    
    -- Test function
    SELECT get_sator_imei_list(test_sator_id) INTO test_result;
    
    RAISE NOTICE 'Result count: %', json_array_length(test_result);
    RAISE NOTICE 'Sample result: %', test_result::text;
  ELSE
    RAISE NOTICE 'No sator found for testing';
  END IF;
END $$;
