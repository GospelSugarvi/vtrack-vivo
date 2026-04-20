DROP FUNCTION IF EXISTS public.get_gudang_stock(uuid, date);

CREATE OR REPLACE FUNCTION public.get_gudang_stock(
  p_sator_id uuid,
  p_tanggal date
)
RETURNS TABLE (
  product_id uuid,
  variant_id uuid,
  product_name text,
  variant text,
  color text,
  price numeric,
  modal numeric,
  srp numeric,
  network_type text,
  qty integer,
  otw integer,
  last_updated timestamp with time zone
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_user_area text;
BEGIN
  SELECT trim(area)
  INTO v_user_area
  FROM public.users
  WHERE id = p_sator_id;

  IF v_user_area IS NULL OR v_user_area = '' THEN
    v_user_area := 'Gudang';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS product_id,
    v.id AS variant_id,
    p.model_name AS product_name,
    v.ram_rom AS variant,
    v.color,
    COALESCE(v.modal, 0) AS price,
    COALESCE(v.modal, 0) AS modal,
    COALESCE(v.srp, 0) AS srp,
    p.network_type,
    COALESCE(wsd.quantity, 0)::integer AS qty,
    0::integer AS otw,
    wsd.updated_at AS last_updated
  FROM public.products p
  JOIN public.product_variants v
    ON p.id = v.product_id
  LEFT JOIN public.warehouse_stock_daily wsd
    ON wsd.variant_id = v.id
   AND wsd.report_date = p_tanggal
   AND lower(trim(COALESCE(wsd.area, wsd.warehouse_code, ''))) =
       lower(trim(v_user_area))
  WHERE p.status = 'active'
    AND v.active = true
    AND p.deleted_at IS NULL
    AND v.deleted_at IS NULL
  ORDER BY p.model_name, COALESCE(v.modal, 0), COALESCE(v.srp, 0);
END;
$$;

ALTER FUNCTION public.get_gudang_stock(uuid, date) SET search_path TO public;
