-- Check bonus_rules table constraints
SELECT 
    tc.constraint_name, 
    tc.constraint_type,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_name = 'bonus_rules';

-- Check if there are any NOT NULL constraints
SELECT column_name, is_nullable, column_default
FROM information_schema.columns 
WHERE table_name = 'bonus_rules'
ORDER BY ordinal_position;
