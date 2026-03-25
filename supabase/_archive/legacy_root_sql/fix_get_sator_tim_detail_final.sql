-- Fix get_sator_tim_detail to return ALL stores

DROP FUNCTION IF EXISTS get_sator_tim_detail(uuid, date);

CREATE OR REPLACE FUNCTION get_sator_tim_detail(
  p_sator_id uuid,
  p_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Build result with all stores and their promotors
  WITH store_data AS (
    SELECT 
      s.id as store_id,
      s.store_name,
      s.area,
      -- Store totals
      COALESCE((
        SELECT COUNT(*)
        FROM sales_sell_out so
        WHERE so.store_id = s.id
          AND so.transaction_date = p_date
          AND so.deleted_at IS NULL
      ), 0) as total_units,
      COALESCE((
        SELECT SUM(price_at_transaction)
        FROM sales_sell_out so
        WHERE so.store_id = s.id
          AND so.transaction_date = p_date
          AND so.deleted_at IS NULL
      ), 0) as total_revenue,
      -- Promotor details
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'promotor_id', u.id,
            'promotor_name', u.full_name,
            'promotor_type', COALESCE(u.promotor_type, 'official'),
            'total_units', COALESCE((
              SELECT COUNT(*)
              FROM sales_sell_out so
              INNER JOIN product_variants pv ON pv.id = so.variant_id
              INNER JOIN products p ON p.id = pv.product_id
              WHERE so.promotor_id = u.id
                AND so.store_id = s.id
                AND so.transaction_date = p_date
                AND so.deleted_at IS NULL
            ), 0),
            'total_revenue', COALESCE((
              SELECT SUM(so.price_at_transaction)
              FROM sales_sell_out so
              WHERE so.promotor_id = u.id
                AND so.store_id = s.id
                AND so.transaction_date = p_date
                AND so.deleted_at IS NULL
            ), 0),
            'fokus_units', COALESCE((
              SELECT COUNT(*)
              FROM sales_sell_out so
              INNER JOIN product_variants pv ON pv.id = so.variant_id
              INNER JOIN products p ON p.id = pv.product_id
              WHERE so.promotor_id = u.id
                AND so.store_id = s.id
                AND so.transaction_date = p_date
                AND so.deleted_at IS NULL
                AND p.is_focus = TRUE
            ), 0),
            'fokus_revenue', COALESCE((
              SELECT SUM(so.price_at_transaction)
              FROM sales_sell_out so
              INNER JOIN product_variants pv ON pv.id = so.variant_id
              INNER JOIN products p ON p.id = pv.product_id
              WHERE so.promotor_id = u.id
                AND so.store_id = s.id
                AND so.transaction_date = p_date
                AND so.deleted_at IS NULL
                AND p.is_focus = TRUE
            ), 0),
            'estimated_bonus', COALESCE((
              SELECT SUM(so.estimated_bonus)
              FROM sales_sell_out so
              WHERE so.promotor_id = u.id
                AND so.store_id = s.id
                AND so.transaction_date = p_date
                AND so.deleted_at IS NULL
            ), 0)
          )
        )
        FROM users u
        INNER JOIN assignments_promotor_store aps 
          ON aps.promotor_id = u.id 
          AND aps.store_id = s.id 
          AND aps.active = true
        WHERE u.role = 'promotor' 
          AND u.deleted_at IS NULL
      ), '[]'::jsonb) as promotors
    FROM stores s
    INNER JOIN assignments_sator_store ass 
      ON ass.store_id = s.id 
      AND ass.sator_id = p_sator_id 
      AND ass.active = true
    WHERE s.deleted_at IS NULL
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'store_id', store_id,
      'store_name', store_name,
      'area', area,
      'total_units', total_units,
      'total_revenue', total_revenue,
      'promotors', promotors
    )
  )
  INTO v_result
  FROM store_data;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_sator_tim_detail(uuid, date) TO authenticated;

-- Test
SELECT 'Function fixed!' as status;
SELECT 'Testing for ANTONIO - should return 16 stores:' as test;
SELECT jsonb_array_length(
  get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
    CURRENT_DATE
  )
) as store_count;

SELECT 'Full result:' as test;
SELECT get_sator_tim_detail(
  (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
  CURRENT_DATE
);
