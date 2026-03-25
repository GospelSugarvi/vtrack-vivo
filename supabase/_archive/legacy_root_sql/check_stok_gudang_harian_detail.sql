-- Check stok_gudang_harian table in detail

-- 1. Table structure
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'stok_gudang_harian'
ORDER BY ordinal_position;

-- 2. Check constraints
SELECT
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_name = 'stok_gudang_harian'
ORDER BY tc.constraint_type, kcu.column_name;

-- 3. Check indexes
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'stok_gudang_harian';

-- 4. Check sample data
SELECT * FROM stok_gudang_harian
ORDER BY tanggal DESC
LIMIT 5;

-- 5. Check if there's any data
SELECT 
    COUNT(*) as total_records,
    MIN(tanggal) as earliest_date,
    MAX(tanggal) as latest_date
FROM stok_gudang_harian;
