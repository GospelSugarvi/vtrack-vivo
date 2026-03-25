-- Recalculate bonus for existing sales data
-- Run this AFTER updating the trigger

DO $$
DECLARE
  sale_record RECORD;
  v_bonus NUMERIC;
  v_promotor_type TEXT;
  v_product_id UUID;
  updated_count INTEGER := 0;
BEGIN
  -- Loop through all existing sales
  FOR sale_record IN 
    SELECT 
      s.id,
      s.price_at_transaction,
      s.promotor_id,
      s.variant_id,
      pv.product_id
    FROM sales_sell_out s
    JOIN product_variants pv ON s.variant_id = pv.id
  LOOP
    v_bonus := 0;
    v_product_id := sale_record.product_id;
    
    -- Get promotor type
    SELECT COALESCE(promotor_type, 'official') INTO v_promotor_type
    FROM users
    WHERE id = sale_record.promotor_id;
    
    -- Calculate bonus using same logic as trigger
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
      AND sale_record.price_at_transaction >= min_price
      AND sale_record.price_at_transaction < COALESCE(max_price, 999999999)
      LIMIT 1;
    END IF;
    
    -- Default to 0 if no rule found
    v_bonus := COALESCE(v_bonus, 0);
    
    -- Update the sale record
    UPDATE sales_sell_out
    SET estimated_bonus = v_bonus
    WHERE id = sale_record.id;
    
    updated_count := updated_count + 1;
  END LOOP;
  
  RAISE NOTICE 'Updated % sales records with recalculated bonus', updated_count;
END $$;

-- Verify results
SELECT 
  COUNT(*) as total_sales,
  SUM(estimated_bonus) as total_bonus,
  AVG(estimated_bonus) as avg_bonus,
  MIN(estimated_bonus) as min_bonus,
  MAX(estimated_bonus) as max_bonus
FROM sales_sell_out;
