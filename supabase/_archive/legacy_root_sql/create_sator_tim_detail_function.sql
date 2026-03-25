-- Create get_sator_tim_detail function
-- Shows stores assigned to sator with their promotors

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
  -- Get stores assigned to this sator with promotor details
  SELECT jsonb_agg(
    jsonb_build_object(
      'store_id', s.id,
      'store_name', s.store_name,
      'area', s.area,
      'total_units', COALESCE(store_totals.total_units, 0),
      'total_revenue', COALESCE(store_totals.total_revenue, 0),
      'promotors', COALESCE(promotor_details.promotor_list, '[]'::jsonb)
    )
  )
  INTO v_result
  FROM stores s
  -- IMPORTANT: Filter by stores assigned to this sator
  INNER JOIN assignments_sator_store ass 
    ON ass.store_id = s.id 
    AND ass.sator_id = p_sator_id 
    AND ass.active = true
  -- Get store totals
  LEFT JOIN LATERAL (
    SELECT 
      COUNT(*) as total_units,
      SUM(price_at_transaction) as total_revenue
    FROM sales_sell_out so
    WHERE so.store_id = s.id
      AND so.transaction_date = p_date
      AND so.deleted_at IS NULL
  ) store_totals ON true
  -- Get promotor details for this store
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'promotor_id', u.id,
        'promotor_name', u.full_name,
        'promotor_type', COALESCE(u.promotor_type, 'official'),
        'total_units', COALESCE(prom_stats.total_units, 0),
        'total_revenue', COALESCE(prom_stats.total_revenue, 0),
        'fokus_units', COALESCE(prom_stats.fokus_units, 0),
        'fokus_revenue', COALESCE(prom_stats.fokus_revenue, 0),
        'estimated_bonus', COALESCE(prom_stats.estimated_bonus, 0)
      )
    ) as promotor_list
    FROM users u
    INNER JOIN assignments_promotor_store aps 
      ON aps.promotor_id = u.id 
      AND aps.store_id = s.id 
      AND aps.active = true
    -- Get promotor statistics
    LEFT JOIN LATERAL (
      SELECT 
        COUNT(*) as total_units,
        SUM(so.price_at_transaction) as total_revenue,
        SUM(CASE WHEN p.is_focus THEN 1 ELSE 0 END) as fokus_units,
        SUM(CASE WHEN p.is_focus THEN so.price_at_transaction ELSE 0 END) as fokus_revenue,
        SUM(so.estimated_bonus) as estimated_bonus
      FROM sales_sell_out so
      INNER JOIN product_variants pv ON pv.id = so.variant_id
      INNER JOIN products p ON p.id = pv.product_id
      WHERE so.promotor_id = u.id
        AND so.store_id = s.id
        AND so.transaction_date = p_date
        AND so.deleted_at IS NULL
    ) prom_stats ON true
    WHERE u.role = 'promotor' 
      AND u.deleted_at IS NULL
  ) promotor_details ON true
  WHERE s.deleted_at IS NULL;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_sator_tim_detail(uuid, date) TO authenticated;

-- Test the function
SELECT 'Function created successfully!' as status;
SELECT 'Testing for ANTONIO...' as test;
SELECT get_sator_tim_detail(
    (SELECT id FROM users WHERE email = 'antonio@sator.vivo'),
    CURRENT_DATE
);
