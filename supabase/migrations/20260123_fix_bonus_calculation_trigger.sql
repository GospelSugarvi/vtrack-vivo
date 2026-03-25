-- Fix bonus calculation trigger to read from bonus_rules table instead of hardcoded

CREATE OR REPLACE FUNCTION process_sell_out_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_bonus NUMERIC := 0;
  v_period_id UUID;
  v_is_focus BOOLEAN;
  v_promotor_type TEXT;
  v_product_id UUID;
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
  
  -- 4. Calculate Bonus from bonus_rules table
  -- PRIORITY 1: Check for flat bonus (product-specific yang sudah ditentukan admin)
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
  
  -- PRIORITY 2: If no flat bonus rule exists (NOT FOUND), use range-based bonus
  -- Note: If flat bonus exists but = 0, it means admin intentionally set 0 bonus
  IF NOT FOUND OR v_bonus IS NULL THEN
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
  END IF;
  
  -- Default to 0 if no rule found
  v_bonus := COALESCE(v_bonus, 0);
  NEW.estimated_bonus := v_bonus;
  
  -- 5. Deduction Stock (Inventory)
  UPDATE store_inventory 
  SET quantity = quantity - 1, last_updated = NOW()
  WHERE store_id = NEW.store_id AND variant_id = NEW.variant_id;
  
  -- 6. Update Aggregation (Rapor)
  INSERT INTO dashboard_performance_metrics (user_id, period_id, total_omzet_real, total_units_sold, total_units_focus)
  VALUES (NEW.promotor_id, v_period_id, NEW.price_at_transaction, 1, CASE WHEN v_is_focus THEN 1 ELSE 0 END)
  ON CONFLICT (user_id, period_id) DO UPDATE SET
    total_omzet_real = dashboard_performance_metrics.total_omzet_real + EXCLUDED.total_omzet_real,
    total_units_sold = dashboard_performance_metrics.total_units_sold + 1,
    total_units_focus = dashboard_performance_metrics.total_units_focus + EXCLUDED.total_units_focus,
    last_updated = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger (in case it doesn't exist)
DROP TRIGGER IF EXISTS trigger_sell_out_process ON sales_sell_out;
CREATE TRIGGER trigger_sell_out_process
BEFORE INSERT ON sales_sell_out
FOR EACH ROW
EXECUTE FUNCTION process_sell_out_insert();

COMMENT ON FUNCTION process_sell_out_insert IS 'Calculate bonus from bonus_rules table based on price range and promotor type';
