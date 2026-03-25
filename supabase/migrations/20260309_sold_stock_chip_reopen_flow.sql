-- Allow sold stock to be reopened as chip inventory after approval.

ALTER TABLE public.stock_chip_requests
ADD COLUMN IF NOT EXISTS request_type TEXT NOT NULL DEFAULT 'fresh_to_chip'
  CHECK (request_type IN ('fresh_to_chip', 'sold_to_chip')),
ADD COLUMN IF NOT EXISTS source_sale_id UUID REFERENCES public.sales_sell_out(id);

CREATE INDEX IF NOT EXISTS idx_stock_chip_requests_request_type
ON public.stock_chip_requests (request_type, status, requested_at DESC);

CREATE OR REPLACE FUNCTION public.submit_sold_stock_chip_request(
  p_imei TEXT,
  p_reason TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_store_id UUID;
  v_stock RECORD;
  v_sale_id UUID;
  v_sator_id UUID;
  v_request_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_imei, '')), '') IS NULL THEN
    RAISE EXCEPTION 'IMEI is required';
  END IF;

  IF NULLIF(TRIM(COALESCE(p_reason, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Reason is required';
  END IF;

  SELECT aps.store_id
  INTO v_store_id
  FROM public.assignments_promotor_store aps
  WHERE aps.promotor_id = v_user_id
    AND aps.active = true
  ORDER BY aps.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_store_id IS NULL THEN
    RAISE EXCEPTION 'Promotor store assignment not found';
  END IF;

  SELECT s.*
  INTO v_stock
  FROM public.stok s
  WHERE s.imei = TRIM(p_imei)
    AND s.store_id = v_store_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Stock IMEI not found in your store';
  END IF;

  IF COALESCE(v_stock.is_sold, false) = false THEN
    RAISE EXCEPTION 'Only sold stock can use this request';
  END IF;

  IF COALESCE(v_stock.tipe_stok, '') = 'chip' THEN
    RAISE EXCEPTION 'Stock is already chip';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.stock_chip_requests r
    WHERE r.stok_id = v_stock.id
      AND r.status = 'pending'
      AND r.request_type = 'sold_to_chip'
  ) THEN
    RAISE EXCEPTION 'Pending sold-to-chip request already exists';
  END IF;

  SELECT sso.id
  INTO v_sale_id
  FROM public.sales_sell_out sso
  WHERE sso.stok_id = v_stock.id
    AND sso.promotor_id = v_user_id
    AND sso.store_id = v_store_id
    AND sso.deleted_at IS NULL
  ORDER BY sso.transaction_date DESC, sso.created_at DESC
  LIMIT 1;

  IF v_sale_id IS NULL THEN
    RAISE EXCEPTION 'Sale history for this IMEI was not found';
  END IF;

  SELECT hsp.sator_id
  INTO v_sator_id
  FROM public.hierarchy_sator_promotor hsp
  WHERE hsp.promotor_id = v_user_id
    AND hsp.active = true
  ORDER BY hsp.created_at DESC NULLS LAST
  LIMIT 1;

  INSERT INTO public.stock_chip_requests (
    stok_id,
    store_id,
    promotor_id,
    sator_id,
    reason,
    request_type,
    source_sale_id
  ) VALUES (
    v_stock.id,
    v_store_id,
    v_user_id,
    v_sator_id,
    TRIM(p_reason),
    'sold_to_chip',
    v_sale_id
  )
  RETURNING id INTO v_request_id;

  UPDATE public.stok
  SET
    pending_chip_reason = TRIM(p_reason),
    chip_requested_by = v_user_id,
    chip_requested_at = NOW(),
    updated_at = NOW()
  WHERE id = v_stock.id;

  RETURN json_build_object(
    'success', true,
    'request_id', v_request_id,
    'stok_id', v_stock.id,
    'imei', v_stock.imei,
    'request_type', 'sold_to_chip'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.review_chip_request(
  p_request_id UUID,
  p_action TEXT,
  p_rejection_note TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_request RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF COALESCE(p_action, '') NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Action must be approved or rejected';
  END IF;

  SELECT r.*
  INTO v_request
  FROM public.stock_chip_requests r
  WHERE r.id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  UPDATE public.stock_chip_requests
  SET
    status = p_action,
    approved_at = NOW(),
    approved_by = v_user_id,
    rejection_note = CASE WHEN p_action = 'rejected' THEN NULLIF(TRIM(COALESCE(p_rejection_note, '')), '') ELSE NULL END
  WHERE id = p_request_id;

  IF p_action = 'approved' THEN
    IF COALESCE(v_request.request_type, 'fresh_to_chip') = 'sold_to_chip' THEN
      UPDATE public.stok
      SET
        is_sold = false,
        sold_at = NULL,
        sold_price = NULL,
        tipe_stok = 'chip',
        chip_reason = v_request.reason,
        chip_approved_by = v_user_id,
        chip_approved_at = NOW(),
        pending_chip_reason = NULL,
        chip_requested_by = NULL,
        chip_requested_at = NULL,
        updated_at = NOW()
      WHERE id = v_request.stok_id;

      INSERT INTO public.stock_movement_log (
        stok_id,
        imei,
        movement_type,
        moved_by,
        moved_at,
        note
      )
      SELECT
        s.id,
        s.imei,
        'chip',
        v_user_id,
        NOW(),
        CONCAT('Reopened sold stock as chip: ', v_request.reason)
      FROM public.stok s
      WHERE s.id = v_request.stok_id;
    ELSE
      UPDATE public.stok
      SET
        tipe_stok = 'chip',
        chip_reason = v_request.reason,
        chip_approved_by = v_user_id,
        chip_approved_at = NOW(),
        pending_chip_reason = NULL,
        chip_requested_by = NULL,
        chip_requested_at = NULL,
        updated_at = NOW()
      WHERE id = v_request.stok_id;

      INSERT INTO public.stock_movement_log (
        stok_id,
        imei,
        movement_type,
        moved_by,
        moved_at,
        note
      )
      SELECT
        s.id,
        s.imei,
        'chip',
        v_user_id,
        NOW(),
        v_request.reason
      FROM public.stok s
      WHERE s.id = v_request.stok_id;
    END IF;
  ELSE
    UPDATE public.stok
    SET
      pending_chip_reason = NULL,
      chip_requested_by = NULL,
      chip_requested_at = NULL,
      updated_at = NOW()
    WHERE id = v_request.stok_id;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_sold_stock_chip_request(TEXT, TEXT) TO authenticated;
