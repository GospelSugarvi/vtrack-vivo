-- Check user_targets table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'user_targets' 
ORDER BY ordinal_position;
