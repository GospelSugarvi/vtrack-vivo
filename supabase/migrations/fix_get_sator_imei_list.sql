-- FIX FINAL: get_sator_imei_list
-- 1. Menggunakan tabel yang benar: imei_normalizations
-- 2. Menggunakan LEFT JOIN agar data tetap muncul meski relasi product/store ada yang null
-- 3. Memastikan filter hirarki sator-promotor berjalan benar

CREATE OR REPLACE FUNCTION get_sator_imei_list(p_sator_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  WITH team_promotors AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', n.id,
      'imei', n.imei,
      'product_name', COALESCE(p.model_name, 'Unknown Product'),
      'variant', COALESCE(pv.ram_rom, '-'),
      'status', n.status,
      'promotor_name', COALESCE(u.full_name, 'Unknown Promotor'),
      'store_name', COALESCE(st.store_name, 'Unknown Store'),
      'created_at', n.created_at
    ) ORDER BY n.created_at DESC
  ), '[]'::json)
  FROM imei_normalizations n
  LEFT JOIN users u ON n.promotor_id = u.id
  LEFT JOIN stores st ON n.store_id = st.id
  LEFT JOIN product_variants pv ON n.variant_id = pv.id
  LEFT JOIN products p ON pv.product_id = p.id
  WHERE n.promotor_id IN (SELECT promotor_id FROM team_promotors);
END;
$$;

-- Opsional: Update constraint status agar fleksibel menerima 'normal' atau 'normalized'
ALTER TABLE imei_normalizations 
DROP CONSTRAINT IF EXISTS imei_normalizations_status_check;

ALTER TABLE imei_normalizations 
ADD CONSTRAINT imei_normalizations_status_check 
CHECK (status IN ('pending', 'sent', 'normal', 'normalized', 'scanned'));
