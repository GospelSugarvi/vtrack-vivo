-- Fix bonus ledger typing at the source.
-- Goals:
-- 1. Determine real bonus type from configured rules, not from bonus_amount > 0.
-- 2. Make process_sell_out_atomic write correct bonus_type for ratio/flat/range/chip.
-- 3. Make validation rebuild path write the same correct bonus_type.
-- 4. Backfill historical sales_bonus_events rows so bonus RPCs read correct source data.

CREATE OR REPLACE FUNCTION public.resolve_sell_out_bonus_type(
  p_promotor_id UUID,
  p_variant_id UUID,
  p_price_at_transaction NUMERIC,
  p_transaction_date DATE,
  p_is_chip_sale BOOLEAN
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_product_id UUID;
BEGIN
  IF COALESCE(p_is_chip_sale, false) THEN
    RETURN 'chip';
  END IF;

  SELECT pv.product_id
  INTO v_product_id
  FROM public.product_variants pv
  WHERE pv.id = p_variant_id;

  IF v_product_id IS NULL THEN
    RETURN 'excluded';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bonus_rules br
    WHERE br.bonus_type = 'flat'
      AND br.product_id = v_product_id
  ) THEN
    RETURN 'flat';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bonus_rules br
    WHERE br.bonus_type = 'ratio'
      AND br.product_id = v_product_id
  ) THEN
    RETURN 'ratio';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.bonus_rules br
    WHERE br.bonus_type = 'range'
      AND p_price_at_transaction >= br.min_price
      AND p_price_at_transaction < COALESCE(br.max_price, 999999999)
  ) THEN
    RETURN 'range';
  END IF;

  RETURN 'excluded';
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_sales_bonus_event_type(
  p_sales_sell_out_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_sale RECORD;
BEGIN
  SELECT
    sso.promotor_id,
    sso.variant_id,
    sso.price_at_transaction,
    sso.transaction_date,
    COALESCE(sso.is_chip_sale, false) AS is_chip_sale
  INTO v_sale
  FROM public.sales_sell_out sso
  WHERE sso.id = p_sales_sell_out_id;

  IF NOT FOUND THEN
    RETURN 'excluded';
  END IF;

  RETURN public.resolve_sell_out_bonus_type(
    v_sale.promotor_id,
    v_sale.variant_id,
    v_sale.price_at_transaction,
    v_sale.transaction_date,
    v_sale.is_chip_sale
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_sales_bonus_event_type()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.bonus_type = 'adjustment' THEN
    RETURN NEW;
  END IF;

  NEW.bonus_type := public.resolve_sales_bonus_event_type(NEW.sales_sell_out_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_sales_bonus_event_type ON public.sales_bonus_events;

CREATE TRIGGER trg_normalize_sales_bonus_event_type
BEFORE INSERT OR UPDATE OF sales_sell_out_id, bonus_type
ON public.sales_bonus_events
FOR EACH ROW
EXECUTE FUNCTION public.normalize_sales_bonus_event_type();

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

  v_bonus_amount := COALESCE(v_estimated_bonus, 0);
  v_bonus_type := public.resolve_sell_out_bonus_type(
    p_promotor_id,
    v_stock.variant_id,
    p_price_at_transaction,
    CURRENT_DATE,
    v_is_chip_sale
  );

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
      'estimated_bonus', v_estimated_bonus,
      'resolved_bonus_type', v_bonus_type
    ),
    v_bonus_amount,
    true,
    '20260321_bonus_type_source_fix_v1',
    CASE
      WHEN v_is_chip_sale THEN 'Chip sale excluded from bonus ledger'
      WHEN v_bonus_amount > 0 THEN 'Seeded from final sales_sell_out.estimated_bonus'
      ELSE 'No bonus payout for this sale, but bonus type preserved from configured rule'
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
    'bonus_amount', v_bonus_amount,
    'bonus_type', v_bonus_type
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.process_verified_sell_out_from_validation(
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
RETURNS JSONB
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

  v_bonus_amount := COALESCE(v_estimated_bonus, 0);
  v_bonus_type := public.resolve_sell_out_bonus_type(
    p_promotor_id,
    v_stock.variant_id,
    p_price_at_transaction,
    CURRENT_DATE,
    v_is_chip_sale
  );

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
      'estimated_bonus', v_estimated_bonus,
      'resolved_bonus_type', v_bonus_type
    ),
    v_bonus_amount,
    true,
    '20260321_bonus_type_source_fix_v1',
    CASE
      WHEN v_is_chip_sale THEN 'Chip sale excluded from bonus ledger'
      WHEN v_bonus_amount > 0 THEN 'Seeded from final sales_sell_out.estimated_bonus'
      ELSE 'No bonus payout for this sale, but bonus type preserved from configured rule'
    END,
    p_promotor_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'sale_id', v_sale_id,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'store_id', v_stock.store_id,
    'variant_id', v_stock.variant_id,
    'is_chip_sale', v_is_chip_sale,
    'estimated_bonus', v_estimated_bonus,
    'bonus_amount', v_bonus_amount,
    'bonus_type', v_bonus_type
  );
END;
$$;

UPDATE public.sales_bonus_events sbe
SET
  bonus_type = public.resolve_sales_bonus_event_type(sbe.sales_sell_out_id),
  rule_snapshot = COALESCE(sbe.rule_snapshot, '{}'::jsonb) || jsonb_build_object(
    'resolved_bonus_type', public.resolve_sales_bonus_event_type(sbe.sales_sell_out_id),
    'source_fix', '20260321_fix_bonus_event_source_types'
  ),
  notes = CASE
    WHEN COALESCE(sbe.notes, '') = '' THEN 'Backfilled bonus type from configured rule'
    WHEN POSITION('Backfilled bonus type from configured rule' IN sbe.notes) > 0 THEN sbe.notes
    ELSE sbe.notes || ' | Backfilled bonus type from configured rule'
  END
WHERE sbe.bonus_type <> 'adjustment';
