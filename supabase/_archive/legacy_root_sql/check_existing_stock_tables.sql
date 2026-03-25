-- Check existing stock-related tables

-- 1. List all tables with 'stock' or 'stok' or 'gudang' in name
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
AND (
    table_name ILIKE '%stock%' 
    OR table_name ILIKE '%stok%'
    OR table_name ILIKE '%gudang%'
    OR table_name ILIKE '%warehouse%'
)
ORDER BY table_name;

-- 2. Check stok_gudang table structure if exists
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'stok_gudang'
ORDER BY ordinal_position;

-- 3. Check warehouse_stock_snapshots if exists
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'warehouse_stock_snapshots'
ORDER BY ordinal_position;

-- 4. Check any other stock tables
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name IN (
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public'
    AND (table_name ILIKE '%stock%' OR table_name ILIKE '%stok%')
)
ORDER BY table_name, ordinal_position;

-- 5. Check sample data if table exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stok_gudang') THEN
        RAISE NOTICE 'Table stok_gudang exists, checking data...';
        PERFORM * FROM stok_gudang LIMIT 1;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'warehouse_stock_snapshots') THEN
        RAISE NOTICE 'Table warehouse_stock_snapshots exists, checking data...';
        PERFORM * FROM warehouse_stock_snapshots LIMIT 1;
    END IF;
END $$;
