-- =====================================================
-- BULK UPSERT STOK GUDANG
-- Created: 2026-02-04
-- Filter by SATOR Area/Warehouse Code
-- =====================================================

-- Drop first to avoid return type conflict
DROP FUNCTION IF EXISTS bulk_upsert_stok_gudang(uuid, date, jsonb);

CREATE OR REPLACE FUNCTION bulk_upsert_stok_gudang(
  p_sator_id UUID,
  p_tanggal DATE,
  p_data JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_area TEXT;
  v_item JSONB;
  v_variant_id UUID;
  v_qty INTEGER;
  v_count INTEGER := 0;
BEGIN
  -- Get user area to use as warehouse_code
  SELECT area INTO v_user_area FROM users WHERE id = p_sator_id;
  
  -- Default to 'Gudang' if no area found (Common fallback)
  IF v_user_area IS NULL OR v_user_area = '' THEN
    v_user_area := 'Gudang';
  END IF;

  -- Process each item
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
  LOOP
    v_variant_id := (v_item->>'variant_id')::UUID;
    v_qty := (v_item->>'stok_gudang')::INTEGER;
    
    -- Upsert into warehouse_stock
    INSERT INTO warehouse_stock (
      warehouse_code,
      area,
      variant_id,
      quantity,
      last_updated
    ) VALUES (
      v_user_area, -- Use Area as Code
      v_user_area,
      v_variant_id,
      v_qty,
      NOW()
    )
    ON CONFLICT (warehouse_code, variant_id)
    DO UPDATE SET
      quantity = EXCLUDED.quantity,
      last_updated = NOW();
      
    v_count := v_count + 1;
  END LOOP;
  
  RETURN json_build_object(
    'success', true,
    'message', format('Successfully updated %s items for warehouse %s', v_count, v_user_area),
    'count', v_count
  );
END;
$$;

-- =====================================================
-- FIX GET_GUDANG_STOCK to filter by Area
-- =====================================================

-- Drop previous versions to avoid signature/return type conflicts
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
  IF v_user_area IS NULL OR v_user_area = '' THEN
    v_user_area := 'Gudang';
  END IF;

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
        'category', CASE 
          WHEN COALESCE(ws.quantity, 0) >= 10 THEN 'plenty'
          WHEN COALESCE(ws.quantity, 0) >= 5 THEN 'enough'
          WHEN COALESCE(ws.quantity, 0) > 0 THEN 'critical'
          ELSE 'empty'
        END
      ) ORDER BY 
        -- Sort logic moved to Frontend, but good to have sensible default here
        COALESCE(ws.quantity, 0) DESC,
        pv.srp ASC
    ), '[]'::json)
    FROM products p
    INNER JOIN product_variants pv ON p.id = pv.product_id
    -- Flexible Left Join (Case Insensitive)
    LEFT JOIN warehouse_stock ws ON pv.id = ws.variant_id 
      AND LOWER(ws.warehouse_code) = LOWER(v_user_area)
    WHERE p.status = 'active' AND pv.active = true
  );
END;
$$;
