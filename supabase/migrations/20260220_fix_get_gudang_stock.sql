-- Drop current function to redefine return type
DROP FUNCTION IF EXISTS get_gudang_stock(uuid, date);

-- Recreate function with network_type included
CREATE OR REPLACE FUNCTION get_gudang_stock(p_sator_id uuid, p_tanggal date)
RETURNS TABLE (
  product_id uuid,
  variant_id uuid,
  product_name text,
  variant text,
  color text,
  price numeric,
  network_type text, -- ADDED: Returns 5G/4G info
  qty integer,
  otw integer,
  last_updated timestamp with time zone
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id as product_id,
    v.id as variant_id,
    p.product_name, -- Ensure consistent column name
    v.ram_storage as variant,
    u.color, -- Using unnested color from subquery/cross join logic below
    v.price,
    p.network_type, -- The missing piece!
    COALESCE(s.qty, 0) as qty,
    COALESCE(s.otw, 0) as otw,
    s.updated_at as last_updated
  FROM products p
  JOIN product_variants v ON p.id = v.product_id
  CROSS JOIN LATERAL UNNEST(p.colors) as u(color) -- Flexible color handling
  LEFT JOIN daily_stock_gudang s ON 
    s.product_id = p.id AND 
    s.variant_id = v.id AND 
    s.color = u.color AND 
    s.input_date = p_tanggal AND
    s.sator_id = p_sator_id
  WHERE p.status = 'active'
  ORDER BY p.product_name, v.price;
END;
$$ LANGUAGE plpgsql;
