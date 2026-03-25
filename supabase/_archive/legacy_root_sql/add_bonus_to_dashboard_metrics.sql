-- ============================================
-- ADD BONUS TO DASHBOARD METRICS
-- Tambah kolom bonus ke dashboard untuk performa
-- ============================================

-- 1. Tambah kolom estimated_bonus_total
ALTER TABLE dashboard_performance_metrics 
ADD COLUMN IF NOT EXISTS estimated_bonus_total NUMERIC DEFAULT 0;

-- 2. Update trigger function untuk include bonus
CREATE OR REPLACE FUNCTION process_sell_out_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_bonus NUMERIC := 0;
  v_period_id UUID;
  v_is_focus BOOLEAN;
  v_promotor_type TEXT;
  v_product_id UUID;
  v_ratio_value INTEGER;
  v_current_sales_count INTEGER;
  v_start_of_month TIMESTAMP;
  v_rule_found BOOLEAN := FALSE;
BEGIN
  -- 1. Find Period
  SELECT id INTO v_period_id FROM target_periods 
  WHERE start_date <= NEW.transaction_date AND end_date >= NEW.transaction_date LIMIT 1;
  
  -- 2. Check Product Focus Status & Get Product ID
  SELECT p.is_focus, p.id INTO v_is_focus, v_product_id 
  FROM products p
  JOIN product_variants pv ON p.id = pv.product_id
  WHERE pv.id = NEW.variant_id;
  
  -- 3. Get Promotor Type (official or training)
  SELECT COALESCE(promotor_type, 'official') INTO v_promotor_type
  FROM users
  WHERE id = NEW.promotor_id;
  
  -- 4. Calculate Bonus
  
  -- PRIORITY 1: Check for FLAT bonus (Highest priority)
  SELECT 
    CASE 
      WHEN v_promotor_type = 'official' THEN COALESCE(bonus_official, flat_bonus)
      ELSE COALESCE(bonus_training, flat_bonus)
    END
  INTO v_bonus
  FROM bonus_rules
  WHERE bonus_type = 'flat' 
  AND product_id = v_product_id
  LIMIT 1;
  
  IF FOUND THEN
      v_rule_found := TRUE;
  ELSE
      -- PRIORITY 2: Check for RATIO bonus (e.g. 2:1)
      SELECT 
        ratio_value,
        CASE 
          WHEN v_promotor_type = 'official' THEN bonus_official
          ELSE bonus_training
        END
      INTO v_ratio_value, v_bonus
      FROM bonus_rules
      WHERE bonus_type = 'ratio' 
      AND product_id = v_product_id
      LIMIT 1;
      
      IF FOUND THEN
          v_rule_found := TRUE;
          
          -- Calculate cumulative sales for this product in current month
          v_start_of_month := date_trunc('month', NEW.transaction_date);
          
          SELECT COUNT(*) INTO v_current_sales_count
          FROM sales_sell_out s
          JOIN product_variants pv ON s.variant_id = pv.id
          WHERE s.promotor_id = NEW.promotor_id
          AND pv.product_id = v_product_id
          AND s.transaction_date >= v_start_of_month
          AND s.transaction_date < (v_start_of_month + interval '1 month');
          
          -- Check if this sales (current_count + 1) completes a set
          v_ratio_value := COALESCE(v_ratio_value, 2);
          
          IF ((v_current_sales_count + 1) % v_ratio_value) != 0 THEN
             -- Not a bonus unit
             v_bonus := 0;
          END IF;
      ELSE
          -- PRIORITY 3: Range Bonus (Fallback)
          SELECT 
            CASE 
              WHEN v_promotor_type = 'official' THEN bonus_official
              ELSE bonus_training
            END
          INTO v_bonus
          FROM bonus_rules
          WHERE bonus_type = 'range'
          AND NEW.price_at_transaction >= min_price
          AND NEW.price_at_transaction < COALESCE(max_price, 999999999)
          LIMIT 1;
          
          IF FOUND THEN
              v_rule_found := TRUE;
          END IF;
      END IF;
  END IF;

  -- Default to 0 if no rule found
  v_bonus := COALESCE(v_bonus, 0);
  NEW.estimated_bonus := v_bonus;
  
  -- 5. Deduction Stock (Inventory)
  UPDATE store_inventory 
  SET quantity = quantity - 1, last_updated = NOW()
  WHERE store_id = NEW.store_id AND variant_id = NEW.variant_id;
  
  -- 6. Update Aggregation (Rapor) - NOW INCLUDING BONUS!
  INSERT INTO dashboard_performance_metrics (
    user_id, 
    period_id, 
    total_omzet_real, 
    total_units_sold, 
    total_units_focus,
    estimated_bonus_total
  )
  VALUES (
    NEW.promotor_id, 
    v_period_id, 
    NEW.price_at_transaction, 
    1, 
    CASE WHEN v_is_focus THEN 1 ELSE 0 END,
    v_bonus
  )
  ON CONFLICT (user_id, period_id) DO UPDATE SET
    total_omzet_real = dashboard_performance_metrics.total_omzet_real + EXCLUDED.total_omzet_real,
    total_units_sold = dashboard_performance_metrics.total_units_sold + 1,
    total_units_focus = dashboard_performance_metrics.total_units_focus + EXCLUDED.total_units_focus,
    estimated_bonus_total = dashboard_performance_metrics.estimated_bonus_total + EXCLUDED.estimated_bonus_total,
    last_updated = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Recalculate existing bonus untuk data yang sudah ada
UPDATE dashboard_performance_metrics dpm
SET estimated_bonus_total = (
  SELECT COALESCE(SUM(so.estimated_bonus), 0)
  FROM sales_sell_out so
  JOIN target_periods tp ON tp.id = dpm.period_id
  WHERE so.promotor_id = dpm.user_id
  AND so.transaction_date >= tp.start_date
  AND so.transaction_date <= tp.end_date
);

-- 4. Verification
SELECT 
  '✅ Bonus column added and populated' as status,
  COUNT(*) as total_records,
  COUNT(CASE WHEN estimated_bonus_total > 0 THEN 1 END) as records_with_bonus,
  SUM(estimated_bonus_total) as total_bonus_in_dashboard
FROM dashboard_performance_metrics;
