-- =====================================================
-- FIX FUNCTION get_sator_aktivitas_tim
-- Menggunakan nama tabel yang benar
-- =====================================================

CREATE OR REPLACE FUNCTION get_sator_aktivitas_tim(
  p_sator_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    WITH promotor_ids AS (
    SELECT promotor_id FROM hierarchy_sator_promotor
    WHERE sator_id = p_sator_id AND active = true
  ),
  store_data AS (
    SELECT DISTINCT
      st.id as store_id,
      st.store_name
    FROM stores st
    INNER JOIN assignments_promotor_store aps ON st.id = aps.store_id
    WHERE aps.promotor_id IN (SELECT promotor_id FROM promotor_ids)
    AND aps.active = true
  ),
  promotor_checklist AS (
    SELECT 
      u.id as promotor_id,
      u.full_name as name,
      aps.store_id,
      -- Check each activity dengan NAMA KOLOM YANG BENAR
      EXISTS(
        SELECT 1 FROM attendance a 
        WHERE a.user_id = u.id 
        AND DATE(a.clock_in AT TIME ZONE 'Asia/Makassar') = p_date
      ) as clock_in,
      EXISTS(
        SELECT 1 FROM sales_sell_out s 
        WHERE s.promotor_id = u.id 
        AND DATE(s.transaction_date AT TIME ZONE 'Asia/Makassar') = p_date
      ) as sell_out,
      EXISTS(
        SELECT 1 FROM stock_validations sv 
        WHERE sv.promotor_id = u.id 
        AND sv.validation_date = p_date
      ) as stock_input,
      EXISTS(
        SELECT 1 FROM promotion_reports pr 
        WHERE pr.promotor_id = u.id 
        AND DATE(pr.created_at AT TIME ZONE 'Asia/Makassar') = p_date
      ) as promotion,
      EXISTS(
        SELECT 1 FROM follower_reports fr 
        WHERE fr.promotor_id = u.id 
        AND DATE(fr.created_at AT TIME ZONE 'Asia/Makassar') = p_date
      ) as follower
    FROM users u
    INNER JOIN promotor_ids pi ON u.id = pi.promotor_id
    INNER JOIN assignments_promotor_store aps ON u.id = aps.promotor_id
    WHERE aps.active = true
  )
  SELECT COALESCE(json_agg(
    json_build_object(
      'store_id', sd.store_id,
      'store_name', sd.store_name,
      'promotors', (
        SELECT COALESCE(json_agg(
          json_build_object(
            'id', pc.promotor_id,
            'name', pc.name,
            'clock_in', pc.clock_in,
            'sell_out', pc.sell_out,
            'stock_input', pc.stock_input,
            'promotion', pc.promotion,
            'follower', pc.follower
          )
        ), '[]'::json)
        FROM promotor_checklist pc
        WHERE pc.store_id = sd.store_id
      )
    )
  ), '[]'::json)
  FROM store_data sd
  );
END;
$$;
