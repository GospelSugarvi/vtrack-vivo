-- Harden transaction correction surface.
-- 1. Only allow proof attachment through a narrow RPC.
-- 2. Remove direct DML privileges on transaction tables.

CREATE OR REPLACE FUNCTION public.attach_sell_out_proof(
  p_sale_id UUID,
  p_image_proof_url TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sale RECORD;
BEGIN
  IF p_sale_id IS NULL THEN
    RAISE EXCEPTION 'p_sale_id is required';
  END IF;

  IF COALESCE(BTRIM(p_image_proof_url), '') = '' THEN
    RAISE EXCEPTION 'p_image_proof_url is required';
  END IF;

  SELECT id, promotor_id, deleted_at
  INTO v_sale
  FROM public.sales_sell_out
  WHERE id = p_sale_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale not found';
  END IF;

  IF v_sale.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot attach proof to deleted sale';
  END IF;

  IF auth.uid() IS NOT NULL AND auth.uid() <> v_sale.promotor_id THEN
    RAISE EXCEPTION 'Unauthorized proof attachment';
  END IF;

  UPDATE public.sales_sell_out
  SET image_proof_url = p_image_proof_url
  WHERE id = p_sale_id;

  RETURN json_build_object(
    'success', true,
    'sale_id', p_sale_id,
    'image_proof_url', p_image_proof_url
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.attach_sell_out_proof(UUID, TEXT) TO authenticated;

DROP POLICY IF EXISTS "Sales update own" ON public.sales_sell_out;

REVOKE INSERT, UPDATE, DELETE ON public.sales_sell_out FROM anon, authenticated;
REVOKE TRUNCATE ON public.sales_sell_out FROM anon, authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.sell_in_orders FROM anon, authenticated;
REVOKE TRUNCATE ON public.sell_in_orders FROM anon, authenticated;
