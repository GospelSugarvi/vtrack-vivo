-- Check current store situation to identify grouping patterns

-- 1. List all stores
SELECT '1. All stores (sorted by name):' as info;
SELECT 
    store_name,
    area,
    grade,
    status
FROM stores 
WHERE deleted_at IS NULL
ORDER BY store_name;

-- 2. Find stores with similar name patterns (potential groups)
SELECT '2. Stores with similar prefixes:' as info;
SELECT 
    CASE 
        WHEN store_name LIKE 'SPC %' THEN 'SPC'
        WHEN store_name LIKE 'MAJU MULIA MANDIRI%' THEN 'MAJU MULIA MANDIRI'
        WHEN store_name LIKE 'ERAFONE%' THEN 'ERAFONE'
        ELSE 'OTHER'
    END as potential_group,
    COUNT(*) as total_stores,
    string_agg(store_name, ', ' ORDER BY store_name) as store_list
FROM stores
WHERE deleted_at IS NULL
GROUP BY potential_group
ORDER BY total_stores DESC, potential_group;

-- 3. Detailed breakdown of potential groups
SELECT '3. SPC stores:' as info;
SELECT store_name FROM stores 
WHERE store_name LIKE 'SPC %' AND deleted_at IS NULL
ORDER BY store_name;

SELECT '4. MAJU MULIA MANDIRI stores:' as info;
SELECT store_name FROM stores 
WHERE store_name LIKE 'MAJU MULIA MANDIRI%' AND deleted_at IS NULL
ORDER BY store_name;

SELECT '5. ERAFONE stores:' as info;
SELECT store_name FROM stores 
WHERE store_name LIKE 'ERAFONE%' AND deleted_at IS NULL
ORDER BY store_name;

-- 6. Check for other potential patterns
SELECT '6. Other potential groups (first word analysis):' as info;
SELECT 
    split_part(store_name, ' ', 1) as first_word,
    COUNT(*) as count,
    string_agg(store_name, ', ' ORDER BY store_name) as stores
FROM stores
WHERE deleted_at IS NULL
AND store_name NOT LIKE 'SPC %'
AND store_name NOT LIKE 'MAJU MULIA MANDIRI%'
AND store_name NOT LIKE 'ERAFONE%'
GROUP BY first_word
HAVING COUNT(*) > 1
ORDER BY count DESC;

-- 7. Total summary
SELECT '7. Summary:' as info;
SELECT 
    COUNT(*) as total_stores,
    COUNT(CASE WHEN store_name LIKE 'SPC %' THEN 1 END) as spc_stores,
    COUNT(CASE WHEN store_name LIKE 'MAJU MULIA MANDIRI%' THEN 1 END) as mmm_stores,
    COUNT(CASE WHEN store_name LIKE 'ERAFONE%' THEN 1 END) as erafone_stores,
    COUNT(CASE 
        WHEN store_name NOT LIKE 'SPC %' 
        AND store_name NOT LIKE 'MAJU MULIA MANDIRI%'
        AND store_name NOT LIKE 'ERAFONE%' 
        THEN 1 
    END) as other_stores
FROM stores
WHERE deleted_at IS NULL;
