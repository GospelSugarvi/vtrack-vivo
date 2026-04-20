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
BEGIN
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
    COALESCE(s.stok_gudang, 0) AS qty,
    COALESCE(s.stok_otw, 0) AS otw,
    s.created_at AS last_updated
  FROM public.products p
  JOIN public.product_variants v
    ON p.id = v.product_id
  LEFT JOIN public.stok_gudang_harian s
    ON s.variant_id = v.id
   AND s.tanggal = p_tanggal
   AND s.created_by = p_sator_id
  WHERE p.status = 'active'
    AND v.active = true
    AND p.deleted_at IS NULL
    AND v.deleted_at IS NULL
  ORDER BY p.model_name, COALESCE(v.modal, 0), COALESCE(v.srp, 0);
END;
$$;

ALTER FUNCTION public.get_gudang_stock(uuid, date) SET search_path TO public;
