-- ==========================================================
-- STOCK RECOMMENDATION & VALIDATION SYNC
-- Created: 2026-02-05
-- ==========================================================

-- 1. Create Stock Rules Table (Admin Settings)
CREATE TABLE IF NOT EXISTS stock_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  grade TEXT NOT NULL, -- 'A', 'B', 'C' (Matches stores.grade)
  product_id UUID REFERENCES products(id), -- Specific product target
  min_qty INTEGER DEFAULT 2,
  ideal_qty INTEGER DEFAULT 5,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed some default rules if empty
INSERT INTO stock_rules (grade, product_id, min_qty, ideal_qty)
SELECT 'A', id, 5, 10 FROM products WHERE status = 'active'
ON CONFLICT DO NOTHING;

INSERT INTO stock_rules (grade, product_id, min_qty, ideal_qty)
SELECT 'B', id, 3, 6 FROM products WHERE status = 'active'
ON CONFLICT DO NOTHING;

INSERT INTO stock_rules (grade, product_id, min_qty, ideal_qty)
SELECT 'C', id, 1, 3 FROM products WHERE status = 'active'
ON CONFLICT DO NOTHING;

-- 2. Sync Validation to Inventory (The Source of Truth)
-- When a validation is 'completed', it overrides the store_inventory
CREATE OR REPLACE FUNCTION sync_validation_to_inventory()
RETURNS TRIGGER AS $$
DECLARE
  v_store_id UUID;
  v_item RECORD;
BEGIN
  -- Only run when status changes to completed
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    
    -- Get store_id (if not in stock_validations, try detailed logic, but we added store_id column earlier)
    v_store_id := NEW.store_id;
    
    IF v_store_id IS NOT NULL THEN
       -- Loop through validated items and update inventory
       -- We count VALIDATED items (is_present = true) grouped by Variant
       FOR v_item IN 
         SELECT 
           s.id as stok_id, 
           pv.id as variant_id,
           COUNT(*) as qty
         FROM stock_validation_items svi
         JOIN stok s ON s.id = svi.stok_id
         JOIN product_variants pv ON pv.id = s.variant_id
         WHERE svi.validation_id = NEW.id 
         AND svi.is_present = true
         GROUP BY pv.id, s.id -- wait, stok_id is unique item? stok table is IMEI?
       LOOP
          -- If stock_validation_items are 1 row per IMEI (stok table linked), 
          -- then we need to aggregate by Variant to update store_inventory (which is quantity based).
          NULL; -- Placeholder logic below
       END LOOP;

       -- CORRECT AGGREGATION:
       -- 1. Clear inventory for this store? No, risky.
       -- 2. Upsert counts based on validation.
       
       -- Better: Aggregate by VARIANT from the validated IMEIs
       FOR v_item IN 
         SELECT 
             s.variant_id, 
             COUNT(*) as val_qty 
         FROM stock_validation_items svi
         JOIN stok s ON s.id = svi.stok_id
         WHERE svi.validation_id = NEW.id 
         AND svi.is_present = true
         GROUP BY s.variant_id
       LOOP
         -- Upsert store_inventory
         INSERT INTO store_inventory (store_id, variant_id, quantity, last_updated)
         VALUES (v_store_id, v_item.variant_id, v_item.val_qty, NOW())
         ON CONFLICT (store_id, variant_id) 
         DO UPDATE SET quantity = EXCLUDED.quantity, last_updated = NOW();
       END LOOP;
       
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_sync_validation_inventory ON stock_validations;
CREATE TRIGGER trigger_sync_validation_inventory
  AFTER UPDATE ON stock_validations
  FOR EACH ROW
  EXECUTE FUNCTION sync_validation_to_inventory();


-- 3. Get Stock Recommendation RPC
DROP FUNCTION IF EXISTS get_store_recommendations(UUID);

CREATE OR REPLACE FUNCTION get_store_recommendations(p_store_id UUID)
RETURNS TABLE (
  product_name TEXT,
  series TEXT,
  network_type TEXT,
  variant_name TEXT,
  color TEXT,
  current_qty INTEGER,
  min_qty INTEGER,
  ideal_qty INTEGER,
  order_qty INTEGER,
  status TEXT -- 'OK', 'LOW', 'EMPTY'
) AS $$
DECLARE
  v_grade TEXT;
BEGIN
  -- Get store grade
  SELECT grade INTO v_grade FROM stores WHERE id = p_store_id;
  IF v_grade IS NULL THEN v_grade := 'C'; END IF; -- Default
  
  RETURN QUERY
  WITH 
  -- 1. Get Active Products & Variants
  base_variants AS (
    SELECT 
      pv.id as variant_id,
      pv.product_id,
      p.model_name,
      p.series,
      p.network_type,
      pv.ram_rom,
      pv.color
    FROM product_variants pv
    JOIN products p ON p.id = pv.product_id
    WHERE p.status = 'active' AND pv.active = true
  ),
  
  -- 2. Validate Inventory (Current Stock)
  current_stock AS (
    SELECT 
      bv.variant_id,
      COALESCE(si.quantity, 0) as qty
    FROM base_variants bv
    LEFT JOIN store_inventory si ON si.variant_id = bv.variant_id AND si.store_id = p_store_id
  ),

  -- 3. Get Sales History (Last 30 Days) for Proportional Logic
  sales_history AS (
    SELECT 
      sso.variant_id,
      COUNT(*) as sold_qty
    FROM sales_sell_out sso
    WHERE sso.store_id = p_store_id 
      AND sso.transaction_date >= (CURRENT_DATE - INTERVAL '30 days')
      AND sso.status = 'completed'
    GROUP BY sso.variant_id
  ),

  -- 4. Calculate Total Sales per Product Model (to decide Flat vs Proportional)
  product_sales AS (
    SELECT 
      bv.product_id,
      COALESCE(SUM(sh.sold_qty), 0) as total_model_sales
    FROM base_variants bv
    LEFT JOIN sales_history sh ON sh.variant_id = bv.variant_id
    GROUP BY bv.product_id
  ),

  -- 5. Count Variants per Product (to split Flat Target)
  variant_counts AS (
    SELECT product_id, COUNT(*) as var_count 
    FROM base_variants 
    GROUP BY product_id
  ),

  -- 6. Get Admin Targets (Total per Model)
  targets AS (
    SELECT 
      sr.product_id,
      sr.min_qty as model_min,
      sr.ideal_qty as model_ideal
    FROM stock_rules sr 
    WHERE sr.grade = v_grade
  ),

  -- 7. ALLOCATION MAGIC (The Brain)
  allocation AS (
      SELECT 
        bv.variant_id,
        bv.product_id,
        ts.model_min,
        ts.model_ideal,
        ps.total_model_sales,
        vc.var_count,
        COALESCE(sh.sold_qty, 0) as variant_sold,
        
        -- LOGIC:
        -- If total_sales < 3: Split Equally (Flat)
        -- If total_sales >= 3: Split Proportionally + Minimum 1 per variant
        CASE 
           WHEN ps.total_model_sales < 3 THEN 
              -- Flat Split (Round Up)
              CEIL(COALESCE(ts.model_ideal, 0)::NUMERIC / GREATEST(vc.var_count, 1))::INTEGER
           ELSE
              -- Proportional Split
              -- Formula: (VariantSold / TotalSold) * Target
              -- Plus logic to ensure every variant gets at least 1 if target allows
              GREATEST(
                1, 
                ROUND((COALESCE(sh.sold_qty, 0)::NUMERIC / ps.total_model_sales) * COALESCE(ts.model_ideal, 0))
              )::INTEGER
        END as target_variant_ideal,

        CASE 
           WHEN ps.total_model_sales < 3 THEN 
              CEIL(COALESCE(ts.model_min, 0)::NUMERIC / GREATEST(vc.var_count, 1))::INTEGER
           ELSE
              GREATEST(
                1, 
                ROUND((COALESCE(sh.sold_qty, 0)::NUMERIC / ps.total_model_sales) * COALESCE(ts.model_min, 0))
              )::INTEGER
        END as target_variant_min

      FROM base_variants bv
      LEFT JOIN product_sales ps ON ps.product_id = bv.product_id
      LEFT JOIN variant_counts vc ON vc.product_id = bv.product_id
      LEFT JOIN targets ts ON ts.product_id = bv.product_id
      LEFT JOIN sales_history sh ON sh.variant_id = bv.variant_id
  )

  -- 8. Final Output
  SELECT 
    bv.model_name,
    bv.series,
    bv.network_type,
    bv.ram_rom,
    bv.color,
    cs.qty::INTEGER as current_qty,
    COALESCE(a.target_variant_min, 0) as min_qty,
    COALESCE(a.target_variant_ideal, 0) as ideal_qty,
    GREATEST(0, COALESCE(a.target_variant_ideal, 0) - cs.qty)::INTEGER as order_qty,
    CASE 
      WHEN cs.qty = 0 THEN 'EMPTY'
      WHEN cs.qty < COALESCE(a.target_variant_min, 1) THEN 'LOW'
      ELSE 'OK'
    END as status
  FROM base_variants bv
  JOIN current_stock cs ON cs.variant_id = bv.variant_id
  LEFT JOIN allocation a ON a.variant_id = bv.variant_id
  ORDER BY status DESC, bv.model_name;
  
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
