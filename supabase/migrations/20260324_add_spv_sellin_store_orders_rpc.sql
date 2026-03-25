DROP FUNCTION IF EXISTS public.get_spv_sellin_store_orders(UUID, UUID, UUID, DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_spv_sellin_store_orders(
  p_spv_id UUID,
  p_sator_id UUID,
  p_store_id UUID,
  p_start_date DATE,
  p_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  IF p_spv_id IS NULL OR p_sator_id IS NULL OR p_store_id IS NULL THEN
    RAISE EXCEPTION 'p_spv_id, p_sator_id, and p_store_id are required';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL THEN
    RAISE EXCEPTION 'p_start_date and p_end_date are required';
  END IF;

  IF p_start_date > p_end_date THEN
    RAISE EXCEPTION 'p_start_date must be before or equal to p_end_date';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.hierarchy_spv_sator hs
    WHERE hs.spv_id = p_spv_id
      AND hs.sator_id = p_sator_id
      AND hs.active = true
  ) THEN
    RAISE EXCEPTION 'SATOR is not under this SPV';
  END IF;

  SELECT json_build_object(
    'store', json_build_object(
      'store_id', st.id,
      'store_name', st.store_name
    ),
    'range', json_build_object(
      'start_date', p_start_date,
      'end_date', p_end_date,
      'label', TO_CHAR(p_start_date, 'DD Mon YYYY') || ' - ' || TO_CHAR(p_end_date, 'DD Mon YYYY')
    ),
    'orders', COALESCE(
      (
        SELECT json_agg(
          json_build_object(
            'id', o.id,
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
            'cancelled_at', o.cancelled_at,
            'items', COALESCE(
              (
                SELECT json_agg(
                  json_build_object(
                    'variant_id', i.variant_id,
                    'qty', i.qty,
                    'price', i.price,
                    'subtotal', i.subtotal,
                    'product_name', p.model_name,
                    'variant', pv.ram_rom,
                    'color', pv.color
                  )
                  ORDER BY p.model_name, pv.ram_rom, pv.color
                )
                FROM public.sell_in_order_items i
                JOIN public.product_variants pv ON pv.id = i.variant_id
                JOIN public.products p ON p.id = pv.product_id
                WHERE i.order_id = o.id
              ),
              '[]'::json
            )
          )
          ORDER BY o.order_date DESC, o.created_at DESC
        )
        FROM public.sell_in_orders o
        WHERE o.sator_id = p_sator_id
          AND o.store_id = p_store_id
          AND o.order_date BETWEEN p_start_date AND p_end_date
      ),
      '[]'::json
    )
  )
  INTO v_result
  FROM public.stores st
  WHERE st.id = p_store_id;

  RETURN COALESCE(
    v_result,
    json_build_object(
      'store', json_build_object(
        'store_id', p_store_id,
        'store_name', 'Toko'
      ),
      'range', json_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'label', TO_CHAR(p_start_date, 'DD Mon YYYY') || ' - ' || TO_CHAR(p_end_date, 'DD Mon YYYY')
      ),
      'orders', '[]'::json
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_spv_sellin_store_orders(UUID, UUID, UUID, DATE, DATE) TO authenticated;
