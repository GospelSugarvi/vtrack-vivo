-- =====================================================
-- CHECK SPC STORES STRUCTURE
-- Date: 20 February 2026
-- Purpose: Analyze stores table and SPC stores grouping
-- =====================================================

-- 1. Check stores table structure
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'stores'
ORDER BY ordinal_position;

-- 2. Check if there's a group/parent column
SELECT * FROM stores LIMIT 1;

-- 3. List all SPC stores
SELECT 
    id,
    store_name,
    area,
    grade,
    status
FROM stores
WHERE store_name ILIKE 'SPC%'
ORDER BY store_name;

-- 4. Count stores by prefix
SELECT 
    CASE 
        WHEN store_name ILIKE 'SPC%' THEN 'SPC Group'
        ELSE 'Other'
    END as store_group,
    COUNT(*) as total_stores
FROM stores
WHERE status = 'active'
GROUP BY store_group;

-- 5. Check if there's existing grouping mechanism
SELECT 
    table_name,
    column_name
FROM information_schema.columns
WHERE column_name ILIKE '%group%' 
   OR column_name ILIKE '%parent%'
   OR column_name ILIKE '%chain%'
ORDER BY table_name;
