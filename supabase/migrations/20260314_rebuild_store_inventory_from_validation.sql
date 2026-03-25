-- Rebuild store_inventory from authoritative sources:
-- 1) latest completed stock validation snapshot per store, then
-- 2) replay sell_in / sell_out events after that snapshot.
-- If a store has never been validated, fall back to current unit-level stok.

CREATE OR REPLACE FUNCTION public.rebuild_store_inventory_for_store(
  p_store_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_validation_id UUID;
  v_validation_created_at TIMESTAMPTZ;
BEGIN
  IF p_store_id IS NULL THEN
    RETURN;
  END IF;

  SELECT sv.id, sv.created_at
  INTO v_validation_id, v_validation_created_at
  FROM public.stock_validations sv
  WHERE sv.store_id = p_store_id
    AND sv.status = 'completed'
  ORDER BY sv.validation_date DESC, sv.created_at DESC
  LIMIT 1;

  DELETE FROM public.store_inventory
  WHERE store_id = p_store_id;

  IF v_validation_id IS NOT NULL THEN
    INSERT INTO public.store_inventory (
      store_id,
      variant_id,
      quantity,
      last_updated
    )
    SELECT
      p_store_id,
      s.variant_id,
      COUNT(*) FILTER (WHERE svi.is_present = true)::INTEGER AS quantity,
      NOW()
    FROM public.stock_validation_items svi
    JOIN public.stok s ON s.id = svi.stok_id
    WHERE svi.validation_id = v_validation_id
    GROUP BY s.variant_id
    HAVING COUNT(*) FILTER (WHERE svi.is_present = true) > 0;

    INSERT INTO public.store_inventory (
      store_id,
      variant_id,
      quantity,
      last_updated
    )
    SELECT
      p_store_id,
      si.variant_id,
      SUM(si.qty)::INTEGER AS quantity,
      NOW()
    FROM public.sales_sell_in si
    WHERE si.store_id = p_store_id
      AND si.deleted_at IS NULL
      AND si.created_at > v_validation_created_at
    GROUP BY si.variant_id
    ON CONFLICT (store_id, variant_id)
    DO UPDATE SET
      quantity = public.store_inventory.quantity + EXCLUDED.quantity,
      last_updated = NOW();

    UPDATE public.store_inventory inv
    SET
      quantity = GREATEST(
        inv.quantity - sold.qty_out,
        0
      ),
      last_updated = NOW()
    FROM (
      SELECT
        so.variant_id,
        COUNT(*)::INTEGER AS qty_out
      FROM public.sales_sell_out so
      WHERE so.store_id = p_store_id
        AND so.deleted_at IS NULL
        AND so.created_at > v_validation_created_at
      GROUP BY so.variant_id
    ) sold
    WHERE inv.store_id = p_store_id
      AND inv.variant_id = sold.variant_id;
  ELSE
    INSERT INTO public.store_inventory (
      store_id,
      variant_id,
      quantity,
      last_updated
    )
    SELECT
      s.store_id,
      s.variant_id,
      COUNT(*) FILTER (WHERE COALESCE(s.is_sold, false) = false)::INTEGER AS quantity,
      NOW()
    FROM public.stok s
    WHERE s.store_id = p_store_id
    GROUP BY s.store_id, s.variant_id
    HAVING COUNT(*) FILTER (WHERE COALESCE(s.is_sold, false) = false) > 0;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.rebuild_store_inventory_all()
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_store_id UUID;
BEGIN
  FOR v_store_id IN
    SELECT DISTINCT store_id
    FROM (
      SELECT id AS store_id FROM public.stores WHERE deleted_at IS NULL
      UNION
      SELECT store_id FROM public.stock_validations WHERE store_id IS NOT NULL
      UNION
      SELECT store_id FROM public.sales_sell_in WHERE store_id IS NOT NULL
      UNION
      SELECT store_id FROM public.sales_sell_out WHERE store_id IS NOT NULL
      UNION
      SELECT store_id FROM public.stok WHERE store_id IS NOT NULL
    ) src
  LOOP
    PERFORM public.rebuild_store_inventory_for_store(v_store_id);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_validation_to_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.store_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'completed' AND (
    TG_OP = 'INSERT'
    OR OLD.status IS DISTINCT FROM 'completed'
    OR OLD.validation_date IS DISTINCT FROM NEW.validation_date
  ) THEN
    PERFORM public.rebuild_store_inventory_for_store(NEW.store_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_validation_inventory ON public.stock_validations;
CREATE TRIGGER trigger_sync_validation_inventory
AFTER INSERT OR UPDATE ON public.stock_validations
FOR EACH ROW
EXECUTE FUNCTION public.sync_validation_to_inventory();

CREATE OR REPLACE FUNCTION public.sync_validation_items_to_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_validation_id UUID;
  v_store_id UUID;
  v_status TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_validation_id := OLD.validation_id;
  ELSE
    v_validation_id := NEW.validation_id;
  END IF;

  SELECT sv.store_id, sv.status
  INTO v_store_id, v_status
  FROM public.stock_validations sv
  WHERE sv.id = v_validation_id;

  IF v_store_id IS NOT NULL AND v_status = 'completed' THEN
    PERFORM public.rebuild_store_inventory_for_store(v_store_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trigger_sync_validation_items_inventory ON public.stock_validation_items;
CREATE TRIGGER trigger_sync_validation_items_inventory
AFTER INSERT OR UPDATE OR DELETE ON public.stock_validation_items
FOR EACH ROW
EXECUTE FUNCTION public.sync_validation_items_to_inventory();

DROP FUNCTION IF EXISTS public.process_sell_out_atomic(
  UUID,UUID,TEXT,NUMERIC,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT
);

CREATE OR REPLACE FUNCTION public.process_sell_out_atomic(
  p_promotor_id UUID,
  p_stok_id UUID,
  p_serial_imei TEXT,
  p_price_at_transaction NUMERIC,
  p_payment_method TEXT,
  p_leasing_provider TEXT,
  p_customer_name TEXT,
  p_customer_phone TEXT,
  p_customer_type TEXT,
  p_image_proof_url TEXT,
  p_notes TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock RECORD;
  v_sale_id UUID;
  v_is_chip_sale BOOLEAN := false;
  v_period_id UUID;
  v_estimated_bonus NUMERIC := 0;
  v_bonus_amount NUMERIC := 0;
  v_bonus_type TEXT := 'excluded';
BEGIN
  IF p_promotor_id IS NULL OR p_stok_id IS NULL OR COALESCE(p_serial_imei, '') = '' THEN
    RAISE EXCEPTION 'p_promotor_id, p_stok_id, and p_serial_imei are required';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> p_promotor_id THEN
    RAISE EXCEPTION 'Unauthorized sell-out context';
  END IF;

  IF COALESCE(p_customer_name, '') = '' THEN
    RAISE EXCEPTION 'Customer name is required';
  END IF;

  IF COALESCE(p_price_at_transaction, 0) <= 0 THEN
    RAISE EXCEPTION 'Price must be greater than 0';
  END IF;

  IF COALESCE(p_payment_method, '') NOT IN ('cash', 'kredit') THEN
    RAISE EXCEPTION 'Payment method must be cash or kredit';
  END IF;

  IF COALESCE(p_customer_type, '') NOT IN ('toko', 'vip_call') THEN
    RAISE EXCEPTION 'Customer type must be toko or vip_call';
  END IF;

  IF p_payment_method = 'kredit' AND COALESCE(p_leasing_provider, '') = '' THEN
    RAISE EXCEPTION 'Leasing provider is required for kredit payment';
  END IF;

  SELECT
    s.id,
    s.imei,
    s.store_id,
    s.variant_id,
    s.is_sold,
    s.tipe_stok
  INTO v_stock
  FROM public.stok s
  WHERE s.id = p_stok_id
    AND s.imei = p_serial_imei
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock/IMEI not found';
  END IF;

  IF v_stock.is_sold THEN
    RAISE EXCEPTION 'IMEI already sold';
  END IF;

  v_is_chip_sale := COALESCE(v_stock.tipe_stok, '') = 'chip';
  v_estimated_bonus := public.calculate_sell_out_estimated_bonus(
    p_promotor_id,
    v_stock.variant_id,
    p_price_at_transaction,
    CURRENT_DATE,
    v_is_chip_sale
  );

  INSERT INTO public.sales_sell_out (
    promotor_id,
    store_id,
    stok_id,
    variant_id,
    transaction_date,
    serial_imei,
    price_at_transaction,
    payment_method,
    leasing_provider,
    status,
    image_proof_url,
    notes,
    customer_name,
    customer_phone,
    customer_type,
    is_chip_sale,
    chip_label_visible,
    estimated_bonus
  ) VALUES (
    p_promotor_id,
    v_stock.store_id,
    v_stock.id,
    v_stock.variant_id,
    CURRENT_DATE,
    v_stock.imei,
    p_price_at_transaction,
    p_payment_method,
    CASE WHEN p_payment_method = 'kredit' THEN p_leasing_provider ELSE NULL END,
    'verified',
    NULLIF(p_image_proof_url, ''),
    NULLIF(p_notes, ''),
    p_customer_name,
    NULLIF(p_customer_phone, ''),
    p_customer_type,
    v_is_chip_sale,
    v_is_chip_sale,
    v_estimated_bonus
  )
  RETURNING id INTO v_sale_id;

  INSERT INTO public.sales_sell_out_status_history (
    sales_sell_out_id,
    old_status,
    new_status,
    notes,
    changed_by
  ) VALUES (
    v_sale_id,
    NULL,
    'verified',
    'Created by process_sell_out_atomic',
    p_promotor_id
  );

  UPDATE public.stok
  SET
    is_sold = true,
    sold_at = COALESCE(sold_at, NOW()),
    sold_price = p_price_at_transaction
  WHERE id = v_stock.id;

  INSERT INTO public.store_inventory (
    store_id,
    variant_id,
    quantity,
    last_updated
  ) VALUES (
    v_stock.store_id,
    v_stock.variant_id,
    0,
    NOW()
  )
  ON CONFLICT (store_id, variant_id)
  DO UPDATE SET
    quantity = GREATEST(public.store_inventory.quantity - 1, 0),
    last_updated = NOW();

  INSERT INTO public.stock_movement_log (
    stok_id,
    imei,
    movement_type,
    moved_by,
    moved_at,
    note
  ) VALUES (
    v_stock.id,
    v_stock.imei,
    'sold',
    p_promotor_id,
    NOW(),
    CONCAT('Sold to ', p_customer_name, ' (', p_customer_type, ')')
  );

  SELECT tp.id
  INTO v_period_id
  FROM public.target_periods tp
  WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
    AND COALESCE(tp.status, 'active') = 'active'
  ORDER BY tp.start_date DESC
  LIMIT 1;

  IF v_is_chip_sale THEN
    v_bonus_amount := 0;
    v_bonus_type := 'chip';
  ELSE
    v_bonus_amount := COALESCE(v_estimated_bonus, 0);
    v_bonus_type := CASE
      WHEN v_bonus_amount > 0 THEN 'range'
      ELSE 'excluded'
    END;
  END IF;

  INSERT INTO public.sales_bonus_events (
    sales_sell_out_id,
    user_id,
    period_id,
    bonus_type,
    rule_snapshot,
    bonus_amount,
    is_projection,
    calculation_version,
    notes,
    created_by
  ) VALUES (
    v_sale_id,
    p_promotor_id,
    v_period_id,
    v_bonus_type,
    jsonb_build_object(
      'source', 'process_sell_out_atomic',
      'stok_id', v_stock.id,
      'tipe_stok', v_stock.tipe_stok,
      'estimated_bonus', v_estimated_bonus
    ),
    v_bonus_amount,
    true,
    '20260314_inventory_hardened_v1',
    CASE
      WHEN v_is_chip_sale THEN 'Chip sale excluded from bonus ledger'
      WHEN v_bonus_amount > 0 THEN 'Seeded from final sales_sell_out.estimated_bonus'
      ELSE 'No bonus for this sale'
    END,
    p_promotor_id
  );

  RETURN json_build_object(
    'success', true,
    'sale_id', v_sale_id,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'store_id', v_stock.store_id,
    'variant_id', v_stock.variant_id,
    'is_chip_sale', v_is_chip_sale,
    'estimated_bonus', v_estimated_bonus,
    'bonus_amount', v_bonus_amount
  );
END;
$$;

SELECT public.rebuild_store_inventory_all();
