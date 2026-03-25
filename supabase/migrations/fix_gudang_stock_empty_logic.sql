-- ==========================================================
-- FIX GUDANG STOCK EMPTY LOGIC
-- Created: 2026-02-20
-- Description: 
-- Ensure get_gudang_stock returns EMPTY LIST [] if no stock data 
-- exists for the requested date. Do not return zero-qty placeholders.
-- ==========================================================

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
  v_has_data BOOLEAN;
BEGIN
  -- 1. Get user area
  SELECT area INTO v_user_area 
  FROM users 
  WHERE id = p_sator_id;
  
  -- Default to 'Gudang' if null
  IF v_user_area IS NULL OR TRIM(v_user_area) = '' THEN
    v_user_area := 'Gudang';
  END IF;
  
  -- Normalize area
  v_user_area := TRIM(v_user_area);

  -- 2. CHECK IF DATA EXISTS for this date and area
  SELECT EXISTS (
    SELECT 1 
    FROM warehouse_stock_daily 
    WHERE LOWER(TRIM(warehouse_code)) = LOWER(v_user_area)
    AND report_date = p_tanggal
  ) INTO v_has_data;

  -- 3. IF NO DATA, RETURN EMPTY LIST IMMEDIATELY
  IF NOT v_has_data THEN
    RETURN '[]'::json;
  END IF;

  -- 4. IF DATA EXISTS, Return the list (joined with products)
  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'product_id', p.id,
        'product_name', p.model_name,
        'variant', pv.ram_rom,
        'color', pv.color,
        'price', pv.srp,
        'qty', COALESCE(wsd.quantity, 0),
        'otw', 0, -- Placeholder for OTW if needed later
        'last_updated', wsd.updated_at,
        'category', CASE 
          WHEN COALESCE(wsd.quantity, 0) >= 10 THEN 'plenty'
          WHEN COALESCE(wsd.quantity, 0) >= 5 THEN 'enough'
          WHEN COALESCE(wsd.quantity, 0) > 0 THEN 'critical'
          ELSE 'empty'
        END
      ) ORDER BY 
        COALESCE(wsd.quantity, 0) DESC,
        p.model_name ASC
    ), '[]'::json)
    FROM products p
    JOIN product_variants pv ON p.id = pv.product_id
    -- Use INNER JOIN or LEFT JOIN depending on requirement. 
    -- Since we already checked EXISTS, using LEFT JOIN here ensures 
    -- we still see all products IF the user has started inputting data 
    -- but maybe missed some products (they will show as 0).
    -- BUT if we want STRICTLY only what was input, allow INNER JOIN?
    -- Requirement says: "halaman ini boleh menampilkan stok apabila user sdh memasukan gambar"
    -- So once they input, we should probably show everything (with 0s for missing) 
    -- OR just show what they scanned. 
    -- Usually for "Stock Opname", we want to see everything to know what is 0.
    LEFT JOIN warehouse_stock_daily wsd ON pv.id = wsd.variant_id 
      AND LOWER(TRIM(wsd.warehouse_code)) = LOWER(v_user_area)
      AND wsd.report_date = p_tanggal
    WHERE p.status = 'active' AND pv.active = true
  );
END;
$$;
