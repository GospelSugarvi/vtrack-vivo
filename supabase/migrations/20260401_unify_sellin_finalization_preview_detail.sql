DROP FUNCTION IF EXISTS public.get_sell_in_order_detail(UUID,UUID);
CREATE OR REPLACE FUNCTION public.get_sell_in_order_detail(
  p_sator_id UUID,
  p_order_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'order', json_build_object(
      'id', o.id,
      'sator_id', o.sator_id,
      'store_id', o.store_id,
      'store_name', st.store_name,
      'group_id', o.group_id,
      'group_name', sg.group_name,
      'order_date', o.order_date,
      'source', o.source,
      'status', o.status,
      'notes', o.notes,
      'cancellation_reason', o.cancellation_reason,
      'total_items', o.total_items,
      'total_qty', o.total_qty,
      'total_value', o.total_value,
      'created_at', o.created_at,
      'finalized_at', o.finalized_at,
      'cancelled_at', o.cancelled_at
    ),
    'items', COALESCE(
      (
        SELECT json_agg(
          json_build_object(
            'variant_id', i.variant_id,
            'qty', i.qty,
            'modal', i.price,
            'price', COALESCE(pv.srp, 0),
            'subtotal', i.subtotal,
            'product_name', p.model_name,
            'variant', pv.ram_rom,
            'color', pv.color,
            'network_type', p.network_type
          ) ORDER BY p.model_name, pv.ram_rom, pv.color
        )
        FROM public.sell_in_order_items i
        JOIN public.product_variants pv ON pv.id = i.variant_id
        JOIN public.products p ON p.id = pv.product_id
        WHERE i.order_id = o.id
      ),
      '[]'::json
    )
  )
  FROM public.sell_in_orders o
  JOIN public.stores st ON st.id = o.store_id
  LEFT JOIN public.store_groups sg ON sg.id = o.group_id
  WHERE o.id = p_order_id
    AND o.sator_id = p_sator_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_sell_in_order_detail(UUID,UUID) TO authenticated;
