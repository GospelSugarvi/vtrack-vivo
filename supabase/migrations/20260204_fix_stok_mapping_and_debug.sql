-- =====================================================
-- FIX STOK GUDANG & MAPPING
-- Created: 2026-02-04
-- =====================================================

-- 1. Ensure `get_products_for_mapping` exists and returns correct structure
DROP FUNCTION IF EXISTS get_products_for_mapping();

CREATE OR REPLACE FUNCTION get_products_for_mapping()
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_agg(
    json_build_object(
      'product_id', p.id,
      'variant_id', pv.id,
      'full_name', TRIM(REGEXP_REPLACE(p.model_name || ' ' || COALESCE(p.series, '') || ' ' || COALESCE(pv.ram_rom, '') || ' ' || COALESCE(pv.color, ''), '\s+', ' ', 'g')),
      'product_name', p.model_name,
      'series', p.series,
      'variant_name', pv.ram_rom,
      'color', pv.color
    )
  )
  FROM products p
  JOIN product_variants pv ON p.id = pv.product_id
  WHERE p.status = 'active' AND pv.active = true;
$$;

-- 2. Update get_gudang_stock with debug fields and better matching
DROP FUNCTION IF EXISTS get_gudang_stock(uuid);
DROP FUNCTION IF EXISTS get_gudang_stock(uuid, date);

CREATE OR REPLACE FUNCTION get_gudang_stock(
  p_sator_id UUID,
  p_tanggal DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_area TEXT;
BEGIN
  -- Get user area
  SELECT area INTO v_user_area FROM users WHERE id = p_sator_id;
  
  -- Default to 'Gudang' if no area found
  IF v_user_area IS NULL OR TRIM(v_user_area) = '' THEN
    v_user_area := 'Gudang';
  END IF;
  
  -- Clean the area string
  v_user_area := TRIM(v_user_area);

  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'product_id', p.id,
        'product_name', p.model_name,
        'variant', pv.ram_rom,
        'color', pv.color,
        'price', pv.srp,
        'qty', COALESCE(ws.quantity, 0),
        'last_updated', ws.last_updated,
        'debug_user_area', v_user_area,
        'debug_warehouse_code', ws.warehouse_code,
        'category', CASE 
          WHEN COALESCE(ws.quantity, 0) >= 10 THEN 'plenty'
          WHEN COALESCE(ws.quantity, 0) >= 5 THEN 'enough'
          WHEN COALESCE(ws.quantity, 0) > 0 THEN 'critical'
          ELSE 'empty'
        END
      ) ORDER BY 
        COALESCE(ws.quantity, 0) DESC,
        pv.srp ASC
    ), '[]'::json)
    FROM products p
    INNER JOIN product_variants pv ON p.id = pv.product_id
    -- Robust Left Join: Case insensitive and ignore whitespace
    LEFT JOIN warehouse_stock ws ON pv.id = ws.variant_id 
      AND (
          LOWER(TRIM(ws.warehouse_code)) = LOWER(v_user_area)
          OR 
          -- Fallback: Check if matching 'Gudang' if specific area fails (optional, but helpful)
          (v_user_area = 'Gudang' AND LOWER(TRIM(ws.warehouse_code)) = 'gudang')
      )
    WHERE p.status = 'active' AND pv.active = true
  );
END;
$$;

-- 3. Debug function to check warehouse stock content
CREATE OR REPLACE FUNCTION debug_check_warehouse_stock()
RETURNS TABLE(
    warehouse_code TEXT,
    quantity INTEGER,
    updated_at TIMESTAMPTZ,
    variant_name TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ws.warehouse_code,
        ws.quantity,
        ws.last_updated,
        pv.ram_rom
    FROM warehouse_stock ws
    JOIN product_variants pv ON ws.variant_id = pv.id
    LIMIT 20;
END;
$$ LANGUAGE plpgsql;
