-- Sell In Finalization MVP
-- Date: 2026-03-03
-- Goal: make Sell In counted only after finalization.

-- 1) Header table for finalized/pending orders
CREATE TABLE IF NOT EXISTS public.sell_in_orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sator_id UUID NOT NULL REFERENCES public.users(id),
  store_id UUID NOT NULL REFERENCES public.stores(id),
  order_date DATE NOT NULL DEFAULT CURRENT_DATE,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'recommendation')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'finalized', 'cancelled')),
  notes TEXT,
  total_items INTEGER NOT NULL DEFAULT 0,
  total_qty INTEGER NOT NULL DEFAULT 0,
  total_value NUMERIC NOT NULL DEFAULT 0,
  finalized_at TIMESTAMPTZ,
  finalized_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sell_in_orders_sator_date
  ON public.sell_in_orders(sator_id, order_date DESC);
CREATE INDEX IF NOT EXISTS idx_sell_in_orders_status
  ON public.sell_in_orders(status, created_at DESC);

-- 2) Detail table per variant
CREATE TABLE IF NOT EXISTS public.sell_in_order_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES public.sell_in_orders(id) ON DELETE CASCADE,
  variant_id UUID NOT NULL REFERENCES public.product_variants(id),
  qty INTEGER NOT NULL CHECK (qty > 0),
  price NUMERIC NOT NULL CHECK (price >= 0),
  subtotal NUMERIC NOT NULL CHECK (subtotal >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(order_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_sell_in_order_items_order
  ON public.sell_in_order_items(order_id);

-- 3) Trigger updated_at
CREATE OR REPLACE FUNCTION public.set_sell_in_orders_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_sell_in_orders_updated_at ON public.sell_in_orders;
CREATE TRIGGER trg_set_sell_in_orders_updated_at
BEFORE UPDATE ON public.sell_in_orders
FOR EACH ROW
EXECUTE FUNCTION public.set_sell_in_orders_updated_at();

-- 4) RLS baseline (read own, no direct write from app)
ALTER TABLE public.sell_in_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sell_in_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own sell_in_orders" ON public.sell_in_orders;
CREATE POLICY "Users read own sell_in_orders"
ON public.sell_in_orders
FOR SELECT
TO authenticated
USING (sator_id = auth.uid());

DROP POLICY IF EXISTS "Users read own sell_in_order_items" ON public.sell_in_order_items;
CREATE POLICY "Users read own sell_in_order_items"
ON public.sell_in_order_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.sell_in_orders o
    WHERE o.id = sell_in_order_items.order_id
      AND o.sator_id = auth.uid()
  )
);

REVOKE INSERT, UPDATE, DELETE ON public.sell_in_orders FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.sell_in_order_items FROM anon, authenticated;

-- 5) Finalization RPC (single source for manual + recommendation)
DROP FUNCTION IF EXISTS public.finalize_sell_in_order(UUID,UUID,DATE,TEXT,TEXT,JSONB);
CREATE OR REPLACE FUNCTION public.finalize_sell_in_order(
  p_sator_id UUID,
  p_store_id UUID,
  p_order_date DATE,
  p_source TEXT,
  p_notes TEXT,
  p_items JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id UUID;
  v_total_items INTEGER := 0;
  v_total_qty INTEGER := 0;
  v_total_value NUMERIC := 0;
  v_store_name TEXT;
BEGIN
  IF p_sator_id IS NULL OR p_store_id IS NULL THEN
    RAISE EXCEPTION 'p_sator_id and p_store_id are required';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items must be a JSON array';
  END IF;

  -- prevent forging another user id from client
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_sator_id THEN
    RAISE EXCEPTION 'Unauthorized finalization context';
  END IF;

  IF COALESCE(p_source, '') NOT IN ('manual', 'recommendation') THEN
    RAISE EXCEPTION 'p_source must be manual or recommendation';
  END IF;

  WITH parsed AS (
    SELECT
      (x->>'variant_id')::UUID AS variant_id,
      GREATEST(COALESCE((x->>'qty')::INTEGER, 0), 0) AS qty
    FROM jsonb_array_elements(p_items) x
  ),
  valid AS (
    SELECT
      p.variant_id,
      p.qty,
      pv.srp::NUMERIC AS price,
      (p.qty * pv.srp::NUMERIC) AS subtotal
    FROM parsed p
    JOIN public.product_variants pv ON pv.id = p.variant_id
    JOIN public.products pr ON pr.id = pv.product_id
    WHERE p.qty > 0
      AND pv.active = true
      AND pr.status = 'active'
  )
  SELECT
    COUNT(*)::INTEGER,
    COALESCE(SUM(qty), 0)::INTEGER,
    COALESCE(SUM(subtotal), 0)::NUMERIC
  INTO v_total_items, v_total_qty, v_total_value
  FROM valid;

  IF v_total_items = 0 OR v_total_qty = 0 THEN
    RAISE EXCEPTION 'No valid order items to finalize';
  END IF;

  INSERT INTO public.sell_in_orders (
    sator_id,
    store_id,
    order_date,
    source,
    status,
    notes,
    total_items,
    total_qty,
    total_value,
    finalized_at,
    finalized_by
  ) VALUES (
    p_sator_id,
    p_store_id,
    COALESCE(p_order_date, CURRENT_DATE),
    p_source,
    'finalized',
    p_notes,
    v_total_items,
    v_total_qty,
    v_total_value,
    NOW(),
    p_sator_id
  )
  RETURNING id INTO v_order_id;

  WITH parsed AS (
    SELECT
      (x->>'variant_id')::UUID AS variant_id,
      GREATEST(COALESCE((x->>'qty')::INTEGER, 0), 0) AS qty
    FROM jsonb_array_elements(p_items) x
  ),
  valid AS (
    SELECT
      p.variant_id,
      p.qty,
      pv.srp::NUMERIC AS price,
      (p.qty * pv.srp::NUMERIC) AS subtotal
    FROM parsed p
    JOIN public.product_variants pv ON pv.id = p.variant_id
    JOIN public.products pr ON pr.id = pv.product_id
    WHERE p.qty > 0
      AND pv.active = true
      AND pr.status = 'active'
  )
  INSERT INTO public.sell_in_order_items (order_id, variant_id, qty, price, subtotal)
  SELECT v_order_id, variant_id, qty, price, subtotal
  FROM valid;

  -- Backward compatibility: keep sales_sell_in feed for existing reports/bonus formulas.
  INSERT INTO public.sales_sell_in (
    sator_id,
    store_id,
    variant_id,
    transaction_date,
    qty,
    total_value,
    notes
  )
  SELECT
    p_sator_id,
    p_store_id,
    i.variant_id,
    COALESCE(p_order_date, CURRENT_DATE),
    i.qty,
    i.subtotal,
    CONCAT('Finalized order #', v_order_id::TEXT, ' (', p_source, ')')
  FROM public.sell_in_order_items i
  WHERE i.order_id = v_order_id;

  SELECT st.store_name INTO v_store_name
  FROM public.stores st
  WHERE st.id = p_store_id;

  RETURN json_build_object(
    'success', true,
    'order_id', v_order_id,
    'store_id', p_store_id,
    'store_name', COALESCE(v_store_name, ''),
    'order_date', COALESCE(p_order_date, CURRENT_DATE),
    'source', p_source,
    'status', 'finalized',
    'total_items', v_total_items,
    'total_qty', v_total_qty,
    'total_value', v_total_value,
    'finalized_at', NOW()
  );
END;
$$;

-- 6) Replace summary + pending RPCs to use finalized model
DROP FUNCTION IF EXISTS public.get_pending_orders(UUID);
CREATE OR REPLACE FUNCTION public.get_pending_orders(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(json_agg(
    json_build_object(
      'id', o.id,
      'store_name', st.store_name,
      'total_items', o.total_items,
      'total_value', o.total_value,
      'status', o.status,
      'created_at', o.created_at
    ) ORDER BY o.created_at DESC
  ), '[]'::json)
  FROM public.sell_in_orders o
  JOIN public.stores st ON st.id = o.store_id
  WHERE o.sator_id = p_sator_id
    AND o.status = 'pending';
$$;

DROP FUNCTION IF EXISTS public.get_sator_sellin_summary(UUID);
CREATE OR REPLACE FUNCTION public.get_sator_sellin_summary(p_sator_id UUID)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH current_period AS (
    SELECT tp.id
    FROM public.target_periods tp
    WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
      AND COALESCE(tp.status, 'active') = 'active'
    ORDER BY tp.start_date DESC
    LIMIT 1
  ),
  finalized_month AS (
    SELECT
      COALESCE(SUM(o.total_value), 0) AS monthly_value,
      COALESCE(SUM(o.total_qty), 0) AS monthly_qty,
      COALESCE(SUM(CASE WHEN o.order_date = CURRENT_DATE THEN o.total_value ELSE 0 END), 0) AS today_value,
      COALESCE(SUM(CASE WHEN o.order_date = CURRENT_DATE THEN o.total_qty ELSE 0 END), 0) AS today_qty
    FROM public.sell_in_orders o
    WHERE o.sator_id = p_sator_id
      AND o.status = 'finalized'
      AND date_trunc('month', o.order_date) = date_trunc('month', CURRENT_DATE)
  ),
  target_data AS (
    SELECT
      COALESCE(
        NULLIF(ut.target_sell_in, 0),
        NULLIF(ut.target_omzet, 0),
        0
      )::NUMERIC AS target_sell_in
    FROM public.user_targets ut
    WHERE ut.user_id = p_sator_id
      AND ut.period_id = (SELECT id FROM current_period)
    LIMIT 1
  )
  SELECT json_build_object(
    -- existing dashboard keys
    'total_sellin', COALESCE((SELECT monthly_value FROM finalized_month), 0),
    'target_sellin', COALESCE((SELECT target_sell_in FROM target_data), 0),
    -- additional keys
    'monthly_value', COALESCE((SELECT monthly_value FROM finalized_month), 0),
    'monthly_qty', COALESCE((SELECT monthly_qty FROM finalized_month), 0),
    'today_value', COALESCE((SELECT today_value FROM finalized_month), 0),
    'today_qty', COALESCE((SELECT today_qty FROM finalized_month), 0)
  );
$$;

GRANT EXECUTE ON FUNCTION public.finalize_sell_in_order(UUID,UUID,DATE,TEXT,TEXT,JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_orders(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sator_sellin_summary(UUID) TO authenticated;
