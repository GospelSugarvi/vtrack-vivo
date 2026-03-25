-- Verify bonus recalculation results
-- This shows the impact of bonus recalculation on leaderboard and totals

-- Step 1: Show current bonus distribution
SELECT 
  'Bonus Distribution' as section,
  '' as detail;

SELECT 
  CASE 
    WHEN estimated_bonus = 0 THEN '0 (No bonus)'
    WHEN estimated_bonus < 25000 THEN '< 25k'
    WHEN estimated_bonus < 50000 THEN '25k - 50k'
    WHEN estimated_bonus < 100000 THEN '50k - 100k'
    ELSE '> 100k'
  END as bonus_range,
  COUNT(*) as sales_count,
  SUM(estimated_bonus) as total_bonus
FROM sales_sell_out
GROUP BY 
  CASE 
    WHEN estimated_bonus = 0 THEN '0 (No bonus)'
    WHEN estimated_bonus < 25000 THEN '< 25k'
    WHEN estimated_bonus < 50000 THEN '25k - 50k'
    WHEN estimated_bonus < 100000 THEN '50k - 100k'
    ELSE '> 100k'
  END
ORDER BY bonus_range;

-- Step 2: Show top earners (current period)
SELECT 
  'Top Earners (Current Period)' as section,
  '' as detail;

SELECT 
  u.full_name,
  u.promotor_type,
  COUNT(s.id) as total_sales,
  SUM(s.estimated_bonus) as total_bonus,
  AVG(s.estimated_bonus) as avg_bonus_per_sale
FROM sales_sell_out s
JOIN users u ON s.promotor_id = u.id
WHERE s.transaction_date >= (SELECT start_date FROM target_periods ORDER BY start_date DESC LIMIT 1)
GROUP BY u.id, u.full_name, u.promotor_type
ORDER BY total_bonus DESC
LIMIT 10;

-- Step 3: Show bonus by product
SELECT 
  'Bonus by Product' as section,
  '' as detail;

SELECT 
  p.model_name,
  COUNT(s.id) as sales_count,
  MIN(s.estimated_bonus) as min_bonus,
  MAX(s.estimated_bonus) as max_bonus,
  AVG(s.estimated_bonus) as avg_bonus,
  SUM(s.estimated_bonus) as total_bonus
FROM sales_sell_out s
JOIN product_variants pv ON s.variant_id = pv.id
JOIN products p ON pv.product_id = p.id
GROUP BY p.id, p.model_name
ORDER BY total_bonus DESC
LIMIT 10;

-- Step 4: Overall summary
SELECT 
  'Overall Summary' as section,
  '' as detail;

SELECT 
  COUNT(*) as total_sales,
  COUNT(DISTINCT promotor_id) as total_promotors,
  SUM(estimated_bonus) as total_bonus_all_time,
  AVG(estimated_bonus) as avg_bonus_per_sale,
  MIN(estimated_bonus) as min_bonus,
  MAX(estimated_bonus) as max_bonus
FROM sales_sell_out;

-- Step 5: Check if any sales have old hardcoded bonus (5000)
SELECT 
  'Sales with old bonus (5000)' as section,
  COUNT(*) as count
FROM sales_sell_out
WHERE estimated_bonus = 5000;
