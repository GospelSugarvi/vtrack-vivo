-- Check product_variants table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'product_variants'
ORDER BY ordinal_position;

-- Check sample variants data
SELECT pv.id, p.model_name, pv.ram, pv.storage, pv.color, pv.srp
FROM product_variants pv
JOIN products p ON pv.product_id = p.id
LIMIT 10;
