-- Harden sell-out pipeline so all writes go through one consistent path.
-- Goals:
-- 1. Calculate estimated_bonus inside process_sell_out_atomic.
-- 2. Remove duplicate/legacy triggers that mutate sales_sell_out implicitly.
-- 3. Backfill legacy sales rows missing stok_id.
-- 4. Reconcile stok.is_sold flags with confirmed sell-out rows.
-- 5. Enforce uniqueness on active non-chip IMEI sales.

CREATE OR REPLACE FUNCTION public.calculate_sell_out_estimated_bonus(
  p_promotor_id UUID,
  p_variant_id UUID,
  p_price_at_transaction NUMERIC,
  p_transaction_date DATE,
  p_is_chip_sale BOOLEAN
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_bonus NUMERIC := 0;
  v_is_focus BOOLEAN := false;
  v_promotor_type TEXT := 'official';
  v_product_id UUID;
  v_ratio_value INTEGER;
  v_current_sales_count INTEGER := 0;
  v_start_of_month TIMESTAMP;
BEGIN
  IF COALESCE(p_is_chip_sale, false) THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(p.is_focus, p.is_fokus, false), p.id
  INTO v_is_focus, v_product_id
  FROM public.products p
  JOIN public.product_variants pv ON pv.product_id = p.id
  WHERE pv.id = p_variant_id;

  SELECT COALESCE(u.promotor_type, 'official')
  INTO v_promotor_type
  FROM public.users u
  WHERE u.id = p_promotor_id;

  SELECT
    CASE
      WHEN v_promotor_type = 'official' THEN COALESCE(br.bonus_official, br.flat_bonus)
      ELSE COALESCE(br.bonus_training, br.flat_bonus)
    END
  INTO v_bonus
  FROM public.bonus_rules br
  WHERE br.bonus_type = 'flat'
    AND br.product_id = v_product_id
  LIMIT 1;

  IF FOUND AND v_bonus IS NOT NULL THEN
    RETURN COALESCE(v_bonus, 0);
  END IF;

  SELECT
    br.ratio_value,
    CASE
      WHEN v_promotor_type = 'official' THEN br.bonus_official
      ELSE br.bonus_training
    END
  INTO v_ratio_value, v_bonus
  FROM public.bonus_rules br
  WHERE br.bonus_type = 'ratio'
    AND br.product_id = v_product_id
  LIMIT 1;

  IF FOUND THEN
    v_start_of_month := date_trunc('month', p_transaction_date);

    SELECT COUNT(*)
    INTO v_current_sales_count
    FROM public.sales_sell_out s
    JOIN public.product_variants pv ON pv.id = s.variant_id
    WHERE s.promotor_id = p_promotor_id
      AND COALESCE(s.is_chip_sale, false) = false
      AND pv.product_id = v_product_id
      AND s.transaction_date >= v_start_of_month
      AND s.transaction_date < (v_start_of_month + interval '1 month')
      AND s.deleted_at IS NULL;

    v_ratio_value := COALESCE(v_ratio_value, 2);
    IF ((v_current_sales_count + 1) % v_ratio_value) != 0 THEN
      RETURN 0;
    END IF;
    RETURN COALESCE(v_bonus, 0);
  END IF;

  SELECT
    CASE
      WHEN v_promotor_type = 'official' THEN br.bonus_official
      ELSE br.bonus_training
    END
  INTO v_bonus
  FROM public.bonus_rules br
  WHERE br.bonus_type = 'range'
    AND p_price_at_transaction >= br.min_price
    AND p_price_at_transaction < COALESCE(br.max_price, 999999999)
  LIMIT 1;

  RETURN COALESCE(v_bonus, 0);
END;
$$;

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
    '20260314_sellout_hardened_v1',
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

DROP TRIGGER IF EXISTS trigger_sell_out_process ON public.sales_sell_out;
DROP TRIGGER IF EXISTS trigger_update_dashboard_metrics ON public.sales_sell_out;

UPDATE public.sales_sell_out so
SET stok_id = s.id
FROM public.stok s
WHERE so.deleted_at IS NULL
  AND COALESCE(so.is_chip_sale, false) = false
  AND so.stok_id IS NULL
  AND s.imei = so.serial_imei
  AND s.store_id = so.store_id
  AND s.variant_id = so.variant_id;

UPDATE public.stok s
SET
  is_sold = true,
  sold_at = COALESCE(s.sold_at, so.created_at),
  sold_price = COALESCE(s.sold_price, so.price_at_transaction)
FROM public.sales_sell_out so
WHERE so.deleted_at IS NULL
  AND COALESCE(so.is_chip_sale, false) = false
  AND s.id = so.stok_id
  AND (
    COALESCE(s.is_sold, false) = false
    OR s.sold_at IS NULL
    OR s.sold_price IS NULL
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_sell_out_active_non_chip_imei
ON public.sales_sell_out (serial_imei)
WHERE deleted_at IS NULL AND COALESCE(is_chip_sale, false) = false;
