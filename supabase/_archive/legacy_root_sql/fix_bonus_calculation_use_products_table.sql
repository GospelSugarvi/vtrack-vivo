-- ============================================
-- FIX: Bonus Calculation - Use Products Table
-- Masalah: Function membaca dari bonus_rules, tapi data ada di products
-- ============================================

CREATE OR REPLACE FUNCTION process_sell_out_insert()
RETURNS TRIGGER AS $$
DECLARE
  v_bonus NUMERIC := 0;
  v_period_id UUID;
  v_is_focus BOOLEAN;
  v_promotor_type TEXT;
  v_product_id UUID;
  v_bonus_type TEXT;
  v_ratio_val INTEGER;
  v_flat_bonus NUMERIC;
  v_current_sales_count INTEGER;
  v_start_of_month TIMESTAMP;
BEGIN
  -- 1. Find Period
  SELECT id INTO v_period_id FROM target_periods 
  WHERE start_date <= NEW.transaction_date AND end_date >= NEW.transaction_date LIMIT 1;
  
  -- 2. Get Product Info (bonus config ada di products table)
  SELECT 
    p.is_focus, 
    p.id,
    p.bonus_type,
    p.ratio_val,
    p.flat_bonus
  INTO v_is_focus, v_product_id, v_bonus_type, v_ratio_val, v_flat_bonus
  FROM products p
  JOIN product_variants pv ON p.id = pv.product_id
  WHERE pv.id = NEW.variant_id;
  
  -- 3. Get Promotor Type (official or training)
  SELECT COALESCE(promotor_type, 'official') INTO v_promotor_type
  FROM users
  WHERE id = NEW.promotor_id;
  
  -- 4. Calculate Bonus based on bonus_type
  
  IF v_bonus_type = 'flat' THEN
    -- FLAT BONUS: Langsung pakai flat_bonus
    v_bonus := COALESCE(v_flat_bonus, 0);
    
  ELSIF v_bonus_type = 'ratio' THEN
    -- RATIO BONUS: 2:1 logic
    -- Hitung berapa unit sudah terjual bulan ini untuk produk ini
    v_start_of_month := date_trunc('month', NEW.transaction_date);
    
    SELECT COUNT(*) INTO v_current_sales_count
    FROM sales_sell_out s
    JOIN product_variants pv ON s.variant_id = pv.id
    WHERE s.promotor_id = NEW.promotor_id
    AND pv.product_id = v_product_id
    AND s.transaction_date >= v_start_of_month
    AND s.transaction_date < (v_start_of_month + interval '1 month');
    
    -- Default ratio adalah 2 (2:1)
    v_ratio_val := COALESCE(v_ratio_val, 2);
    
    -- Logic: Unit ke-2, 4, 6, 8, dst dapat bonus
    -- Unit ke-1, 3, 5, 7, dst tidak dapat bonus
    IF ((v_current_sales_count + 1) % v_ratio_val) = 0 THEN
      -- Ini unit yang dapat bonus
      -- Bonus untuk ratio products:
      -- Official: Rp 5.000, Training: Rp 4.000
      IF v_promotor_type = 'official' THEN
        v_bonus := 5000;
      ELSE
        v_bonus := 4000;
      END IF;
    ELSE
      -- Unit ganjil, tidak dapat bonus
      v_bonus := 0;
    END IF;
    
  ELSE
    -- RANGE BONUS: Berdasarkan harga (fallback)
    -- Cek di bonus_rules table jika ada
    BEGIN
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
    EXCEPTION
      WHEN OTHERS THEN
        -- bonus_rules table mungkin tidak ada, default ke 0
        v_bonus := 0;
    END;
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
      -- Ignore inventory errors
      NULL;
  END;
  
  -- 6. Update Aggregation (Rapor)
  BEGIN
    INSERT INTO dashboard_performance_metrics (
      user_id, 
      period_id, 
      total_omzet_real, 
      total_units_sold, 
      total_units_focus
    )
    VALUES (
      NEW.promotor_id, 
      v_period_id, 
      NEW.price_at_transaction, 
      1, 
      CASE WHEN v_is_focus THEN 1 ELSE 0 END
    )
    ON CONFLICT (user_id, period_id) DO UPDATE SET
      total_omzet_real = dashboard_performance_metrics.total_omzet_real + EXCLUDED.total_omzet_real,
      total_units_sold = dashboard_performance_metrics.total_units_sold + 1,
      total_units_focus = dashboard_performance_metrics.total_units_focus + EXCLUDED.total_units_focus,
      last_updated = NOW();
  EXCEPTION
    WHEN OTHERS THEN
      -- Ignore aggregation errors
      NULL;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger
DROP TRIGGER IF EXISTS trigger_sell_out_process ON sales_sell_out;
CREATE TRIGGER trigger_sell_out_process
BEFORE INSERT ON sales_sell_out
FOR EACH ROW EXECUTE FUNCTION process_sell_out_insert();

-- Verification
SELECT 
  '=== VERIFICATION ===' as status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.routines 
      WHERE routine_name = 'process_sell_out_insert'
    )
    THEN '✅ Function updated'
    ELSE '❌ Function not found'
  END as function_status,
  CASE 
    WHEN EXISTS (
      SELECT 1 FROM information_schema.triggers 
      WHERE trigger_name = 'trigger_sell_out_process'
    )
    THEN '✅ Trigger active'
    ELSE '❌ Trigger not found'
  END as trigger_status;
