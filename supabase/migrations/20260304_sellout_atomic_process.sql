-- Sell Out atomic transaction process
-- Date: 2026-03-04
-- Goal: prevent partial write and duplicate IMEI sale due to race/double-submit.

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

  -- Lock stock row to avoid concurrent sell for the same IMEI
  SELECT s.id, s.imei, s.store_id, s.variant_id, s.is_sold, s.tipe_stok
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
    chip_label_visible
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
    v_is_chip_sale
  ) RETURNING id INTO v_sale_id;

  UPDATE public.stok
  SET
    is_sold = true,
    sold_at = NOW(),
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

  RETURN json_build_object(
    'success', true,
    'sale_id', v_sale_id,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'store_id', v_stock.store_id,
    'variant_id', v_stock.variant_id,
    'is_chip_sale', v_is_chip_sale
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_sell_out_atomic(
  UUID,UUID,TEXT,NUMERIC,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT
) TO authenticated;
