-- Add explicit cancellation flow for sell-in orders.

ALTER TABLE public.sell_in_orders
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

DROP FUNCTION IF EXISTS public.cancel_sell_in_order_by_id(UUID,UUID,TEXT,TEXT);
CREATE OR REPLACE FUNCTION public.cancel_sell_in_order_by_id(
  p_sator_id UUID,
  p_order_id UUID,
  p_reason TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_reason TEXT;
BEGIN
  IF p_sator_id IS NULL OR p_order_id IS NULL THEN
    RAISE EXCEPTION 'p_sator_id and p_order_id are required';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_sator_id THEN
    RAISE EXCEPTION 'Unauthorized cancellation context';
  END IF;

  v_reason := NULLIF(TRIM(COALESCE(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Cancellation reason is required';
  END IF;

  SELECT *
  INTO v_order
  FROM public.sell_in_orders o
  WHERE o.id = p_order_id
    AND o.sator_id = p_sator_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found for this user';
  END IF;

  IF v_order.status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending order can be cancelled';
  END IF;

  UPDATE public.sell_in_orders
  SET
    status = 'cancelled',
    cancelled_at = NOW(),
    cancelled_by = p_sator_id,
    cancellation_reason = v_reason,
    notes = COALESCE(NULLIF(TRIM(COALESCE(p_notes, '')), ''), notes)
  WHERE id = p_order_id;

  INSERT INTO public.sell_in_order_status_history (
    order_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) VALUES (
    p_order_id,
    'pending',
    'cancelled',
    CONCAT('Cancelled: ', v_reason),
    p_sator_id
  );

  RETURN json_build_object(
    'success', true,
    'order_id', v_order.id,
    'status', 'cancelled',
    'cancelled_at', NOW(),
    'cancellation_reason', v_reason,
    'total_items', v_order.total_items,
    'total_qty', v_order.total_qty,
    'total_value', v_order.total_value
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_sell_in_order_by_id(UUID,UUID,TEXT,TEXT) TO authenticated;

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
            'price', i.price,
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

DROP FUNCTION IF EXISTS public.get_sell_in_finalization_summary(UUID);
CREATE OR REPLACE FUNCTION public.get_sell_in_finalization_summary(
  p_sator_id UUID
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'pending_order_count', COUNT(*) FILTER (WHERE o.status = 'pending'),
    'pending_total_items', COALESCE(SUM(o.total_items) FILTER (WHERE o.status = 'pending'), 0),
    'pending_total_qty', COALESCE(SUM(o.total_qty) FILTER (WHERE o.status = 'pending'), 0),
    'pending_total_value', COALESCE(SUM(o.total_value) FILTER (WHERE o.status = 'pending'), 0),
    'finalized_order_count', COUNT(*) FILTER (WHERE o.status = 'finalized'),
    'finalized_total_items', COALESCE(SUM(o.total_items) FILTER (WHERE o.status = 'finalized'), 0),
    'finalized_total_qty', COALESCE(SUM(o.total_qty) FILTER (WHERE o.status = 'finalized'), 0),
    'finalized_total_value', COALESCE(SUM(o.total_value) FILTER (WHERE o.status = 'finalized'), 0),
    'cancelled_order_count', COUNT(*) FILTER (WHERE o.status = 'cancelled'),
    'cancelled_total_items', COALESCE(SUM(o.total_items) FILTER (WHERE o.status = 'cancelled'), 0),
    'cancelled_total_qty', COALESCE(SUM(o.total_qty) FILTER (WHERE o.status = 'cancelled'), 0),
    'cancelled_total_value', COALESCE(SUM(o.total_value) FILTER (WHERE o.status = 'cancelled'), 0)
  )
  FROM public.sell_in_orders o
  WHERE o.sator_id = p_sator_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_sell_in_finalization_summary(UUID) TO authenticated;
