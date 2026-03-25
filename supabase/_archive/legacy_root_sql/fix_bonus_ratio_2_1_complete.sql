-- ============================================
-- FIX COMPLETE: Bonus Ratio 2:1 System
-- Untuk produk Y02, Y03T, Y04S
-- ============================================

-- STEP 1: Pastikan kolom ratio_value ada di bonus_rules
ALTER TABLE bonus_rules ADD COLUMN IF NOT EXISTS ratio_value INTEGER DEFAULT 2;

-- STEP 2: Pastikan constraint bonus_type include 'ratio'
DO $$
BEGIN
  -- Drop old constraint if exists
  ALTER TABLE bonus_rules DROP CONSTRAINT IF EXISTS bonus_rules_bonus_type_check;
  
  -- Add new constraint
  ALTER TABLE bonus_rules ADD CONSTRAINT bonus_rules_bonus_type_check 
    CHECK (bonus_type IN ('range', 'flat', 'ratio'));
    
  RAISE NOTICE '✅ Constraint updated to include ratio type';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '⚠️  Constraint already exists or error: %', SQLERRM;
END $$;

-- STEP 3: Update/Create function process_sell_out_insert dengan logic ratio 2:1
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
      -- This is for products like Y02 where you sell 2 to get 1 bonus
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
          -- Default ratio is 2 (buy 2 get 1 bonus)
          v_ratio_value := COALESCE(v_ratio_value, 2);
          
          -- Logic: Unit ke-2, 4, 6, 8, dst dapat bonus
          -- Unit ke-1, 3, 5, 7, dst tidak dapat bonus
          IF ((v_current_sales_count + 1) % v_ratio_value) != 0 THEN
             -- Not a bonus unit (e.g. unit 1, 3, 5...)
             v_bonus := 0;
          END IF;
          -- Else: bonus sudah di-set dari SELECT di atas
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
  
  -- 5. Deduction Stock (Inventory) - with error handling
  BEGIN
    UPDATE store_inventory 
    SET quantity = quantity - 1, last_updated = NOW()
    WHERE store_id = NEW.store_id AND variant_id = NEW.variant_id;
  EXCEPTION
    WHEN OTHERS THEN
      -- Ignore inventory errors, just log
      RAISE NOTICE 'Inventory update failed: %', SQLERRM;
  END;
  
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

-- STEP 4: Recreate trigger
DROP TRIGGER IF EXISTS trigger_sell_out_process ON sales_sell_out;
CREATE TRIGGER trigger_sell_out_process
BEFORE INSERT ON sales_sell_out
FOR EACH ROW EXECUTE FUNCTION process_sell_out_insert();

-- STEP 5: Setup bonus rules untuk Y02, Y03T, Y04S (jika belum ada)
DO $$
DECLARE
  y02_id UUID;
  y03t_id UUID;
  y04s_id UUID;
BEGIN
  -- Get product IDs
  SELECT id INTO y02_id FROM products WHERE model_name = 'Y02' LIMIT 1;
  SELECT id INTO y03t_id FROM products WHERE model_name = 'Y03T' LIMIT 1;
  SELECT id INTO y04s_id FROM products WHERE model_name = 'Y04S' LIMIT 1;
  
  -- Y02
  IF y02_id IS NOT NULL THEN
    INSERT INTO bonus_rules (
      bonus_type,
      product_id,
      ratio_value,
      bonus_official,
      bonus_training
    ) VALUES (
      'ratio',
      y02_id,
      2,  -- 2:1 ratio
      5000,  -- Rp 5.000 untuk official
      4000   -- Rp 4.000 untuk training
    )
    ON CONFLICT DO NOTHING;
    RAISE NOTICE '✅ Y02 ratio bonus rule created/exists';
  ELSE
    RAISE NOTICE '⚠️  Y02 product not found, skipping bonus rule';
  END IF;
  
  -- Y03T
  IF y03t_id IS NOT NULL THEN
    INSERT INTO bonus_rules (
      bonus_type,
      product_id,
      ratio_value,
      bonus_official,
      bonus_training
    ) VALUES (
      'ratio',
      y03t_id,
      2,
      5000,
      4000
    )
    ON CONFLICT DO NOTHING;
    RAISE NOTICE '✅ Y03T ratio bonus rule created/exists';
  ELSE
    RAISE NOTICE '⚠️  Y03T product not found, skipping bonus rule';
  END IF;
  
  -- Y04S
  IF y04s_id IS NOT NULL THEN
    INSERT INTO bonus_rules (
      bonus_type,
      product_id,
      ratio_value,
      bonus_official,
      bonus_training
    ) VALUES (
      'ratio',
      y04s_id,
      2,
      5000,
      4000
    )
    ON CONFLICT DO NOTHING;
    RAISE NOTICE '✅ Y04S ratio bonus rule created/exists';
  ELSE
    RAISE NOTICE '⚠️  Y04S product not found, skipping bonus rule';
  END IF;
END $$;

-- STEP 6: Recalculate existing sales (optional, jika ada data lama)
-- Uncomment jika ingin recalculate semua sales yang sudah ada
/*
DO $$
DECLARE
  sale_record RECORD;
  v_bonus NUMERIC;
  v_promotor_type TEXT;
  v_product_id UUID;
  v_ratio_value INTEGER;
  v_current_sales_count INTEGER;
  v_start_of_month TIMESTAMP;
  updated_count INT := 0;
BEGIN
  FOR sale_record IN 
    SELECT so.*, pv.product_id
    FROM sales_sell_out so
    JOIN product_variants pv ON pv.id = so.variant_id
    JOIN products p ON p.id = pv.product_id
    WHERE p.model_name IN ('Y02', 'Y03T', 'Y04S')
    ORDER BY so.promotor_id, pv.product_id, so.transaction_date
  LOOP
    -- Get promotor type
    SELECT COALESCE(promotor_type, 'official') INTO v_promotor_type
    FROM users WHERE id = sale_record.promotor_id;
    
    -- Get ratio rule
    SELECT 
      ratio_value,
      CASE 
        WHEN v_promotor_type = 'official' THEN bonus_official
        ELSE bonus_training
      END
    INTO v_ratio_value, v_bonus
    FROM bonus_rules
    WHERE bonus_type = 'ratio' 
    AND product_id = sale_record.product_id;
    
    IF FOUND THEN
      -- Calculate position in month
      v_start_of_month := date_trunc('month', sale_record.transaction_date);
      
      SELECT COUNT(*) INTO v_current_sales_count
      FROM sales_sell_out s
      JOIN product_variants pv ON s.variant_id = pv.id
      WHERE s.promotor_id = sale_record.promotor_id
      AND pv.product_id = sale_record.product_id
      AND s.transaction_date >= v_start_of_month
      AND s.transaction_date < sale_record.transaction_date;
      
      -- Check if this unit gets bonus
      IF ((v_current_sales_count + 1) % v_ratio_value) != 0 THEN
        v_bonus := 0;
      END IF;
      
      -- Update
      UPDATE sales_sell_out
      SET estimated_bonus = v_bonus
      WHERE id = sale_record.id;
      
      updated_count := updated_count + 1;
    END IF;
  END LOOP;
  
  RAISE NOTICE '✅ Recalculated % sales records', updated_count;
END $$;
*/

-- STEP 7: Verification
SELECT 
  '=== VERIFICATION ===' as status,
  CASE 
    WHEN EXISTS (SELECT 1 FROM bonus_rules WHERE bonus_type = 'ratio')
    THEN '✅ Ratio bonus rules exist'
    ELSE '❌ No ratio bonus rules'
  END as ratio_rules,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'bonus_rules' AND column_name = 'ratio_value'
    )
    THEN '✅ ratio_value column exists'
    ELSE '❌ ratio_value column missing'
  END as column_check,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.routines 
      WHERE routine_name = 'process_sell_out_insert'
    )
    THEN '✅ Trigger function exists'
    ELSE '❌ Trigger function missing'
  END as function_check;
