-- Check current schedules table structure

-- 1. Check table columns
SELECT 
    column_name,
    data_type,
    character_maximum_length,
    column_default,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'schedules'
ORDER BY ordinal_position;

-- 2. Check constraints
SELECT 
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'schedules';

-- 3. Check indexes
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'schedules';

-- 4. Check sample data (if any)
SELECT 
    COUNT(*) as total_records,
    MIN(schedule_date) as earliest_date,
    MAX(schedule_date) as latest_date,
    COUNT(DISTINCT promotor_id) as total_promotors,
    COUNT(DISTINCT status) as status_count
FROM schedules;

-- 5. Check status values
SELECT 
    status,
    COUNT(*) as count
FROM schedules
GROUP BY status;

-- 6. Check shift_type values
SELECT 
    shift_type,
    COUNT(*) as count
FROM schedules
GROUP BY shift_type;
