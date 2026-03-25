-- =====================================================
-- FIX DAILY STOCK DISPLAY
-- Created: 2026-02-05
-- Description:
-- 1. Create a Snapshot/History table `warehouse_stock_daily` to store daily records.
-- 2. Update `bulk_upsert_stok_gudang` to save to BOTH `warehouse_stock` (current) and `warehouse_stock_daily` (history).
-- 3. Update `get_gudang_stock` to read from `warehouse_stock_daily` if filtering by date, or strictly enforce date matching.
-- =====================================================

-- 1. Create Daily History Table
CREATE TABLE IF NOT EXISTS warehouse_stock_daily (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    warehouse_code TEXT NOT NULL,
    area TEXT,
    variant_id UUID REFERENCES product_variants(id) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    report_date DATE NOT NULL DEFAULT CURRENT_DATE, -- The 'business' date of the stock
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(warehouse_code, variant_id, report_date)
);

-- Enable RLS
ALTER TABLE warehouse_stock_daily ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SATOR can view/manage their own daily stock" ON warehouse_stock_daily;

CREATE POLICY "SATOR can view/manage their own daily stock" ON warehouse_stock_daily
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM users 
    WHERE users.id = auth.uid() 
    AND users.role IN ('sator', 'admin', 'spv', 'manager')
  )
);

-- 2. Update Bulk Upsert to Save to History
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
  SELECT TRIM(area) INTO v_user_area FROM users WHERE id = p_sator_id;
  
  IF v_user_area IS NULL OR v_user_area = '' THEN
    v_user_area := 'Gudang'; -- Fallback
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
  LOOP
    v_variant_id := (v_item->>'variant_id')::UUID;
    v_qty := (v_item->>'stok_gudang')::INTEGER;
    
    -- A. Update Current Stock (cache)
    INSERT INTO warehouse_stock (
      warehouse_code, area, variant_id, quantity, last_updated
    ) VALUES (
      v_user_area, v_user_area, v_variant_id, v_qty, NOW()
    )
    ON CONFLICT (warehouse_code, variant_id)
    DO UPDATE SET
      quantity = EXCLUDED.quantity,
      last_updated = NOW();

    -- B. Upsert into Daily History Table
    INSERT INTO warehouse_stock_daily (
      warehouse_code, area, variant_id, quantity, report_date, updated_at
    ) VALUES (
      v_user_area, v_user_area, v_variant_id, v_qty, p_tanggal, NOW()
    )
    ON CONFLICT (warehouse_code, variant_id, report_date)
    DO UPDATE SET
      quantity = EXCLUDED.quantity,
      updated_at = NOW();
      
    v_count := v_count + 1;
  END LOOP;
  
  RETURN json_build_object('success', true, 'count', v_count, 'area', v_user_area, 'date', p_tanggal);
END;
$$;

-- 3. Update Getter to Use Daily Table for Specific Date
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
  
  -- Default to 'Gudang'
  IF v_user_area IS NULL OR TRIM(v_user_area) = '' THEN
    v_user_area := 'Gudang';
  END IF;
  
  v_user_area := TRIM(v_user_area);

  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'product_id', p.id,
        'product_name', p.model_name,
        'variant', pv.ram_rom,
        'color', pv.color,
        'price', pv.srp,
        'qty', COALESCE(wsd.quantity, 0), -- Use Daily Quantity
        'last_updated', wsd.updated_at,
        'category', CASE 
          WHEN COALESCE(wsd.quantity, 0) >= 10 THEN 'plenty'
          WHEN COALESCE(wsd.quantity, 0) >= 5 THEN 'enough'
          WHEN COALESCE(wsd.quantity, 0) > 0 THEN 'critical'
          ELSE 'empty'
        END
      ) ORDER BY 
        COALESCE(wsd.quantity, 0) DESC,
        pv.srp ASC
    ), '[]'::json)
    FROM products p
    INNER JOIN product_variants pv ON p.id = pv.product_id
    -- JOIN with Daily Table filtered by p_tanggal
    LEFT JOIN warehouse_stock_daily wsd ON pv.id = wsd.variant_id 
      AND LOWER(TRIM(wsd.warehouse_code)) = LOWER(v_user_area)
      AND wsd.report_date = p_tanggal -- STRICTLY MATCH DATE
    WHERE p.status = 'active' AND pv.active = true
  );
END;
$$;
