-- Update get_team_live_feed to support date filtering.
-- Date: 2026-03-12

DROP FUNCTION IF EXISTS public.get_team_live_feed(UUID);
CREATE OR REPLACE FUNCTION public.get_team_live_feed(
  p_sator_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'id', s.id,
        'type', 'sell_out',
        'promotor_id', u.id,
        'promotor_name', u.full_name,
        'store_name', st.store_name,
        'product_name', COALESCE(p.model_name, 'Produk'),
        'variant_name', COALESCE(pv.ram_rom, ''),
        'price', s.price_at_transaction,
        'bonus', s.estimated_bonus,
        'created_at', s.created_at
      ) ORDER BY s.created_at DESC
    ), '[]'::json)
    FROM sales_sell_out s
    INNER JOIN users u ON u.id = s.promotor_id
    LEFT JOIN stores st ON st.id = s.store_id
    LEFT JOIN product_variants pv ON pv.id = s.variant_id
    LEFT JOIN products p ON p.id = pv.product_id
    WHERE s.promotor_id IN (
      SELECT promotor_id FROM hierarchy_sator_promotor
      WHERE sator_id = p_sator_id AND active = true
    )
    AND s.transaction_date = p_date
    AND s.deleted_at IS NULL
    AND COALESCE(s.is_chip_sale, false) = false
    LIMIT 50
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_team_live_feed(UUID, DATE) TO authenticated;

