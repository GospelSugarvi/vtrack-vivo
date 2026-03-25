-- ============================================
-- DEBUG: IMEI Normalization - Sator View
-- Memeriksa kenapa data dari Promotor tidak muncul di Sator
-- ============================================

-- 1. CEK DATA IMEI NORMALIZATION YANG ADA
SELECT 
    'Total IMEI Normalization Records' as check_type,
    COUNT(*) as total,
    COUNT(DISTINCT promotor_id) as total_promotors,
    COUNT(DISTINCT store_id) as total_stores,
    MIN(created_at) as oldest_record,
    MAX(created_at) as newest_record
FROM imei_normalizations;

-- 2. CEK DATA PER STATUS
SELECT 
    'IMEI by Status' as check_type,
    status,
    COUNT(*) as total,
    COUNT(DISTINCT promotor_id) as promotors,
    COUNT(DISTINCT store_id) as stores
FROM imei_normalizations
GROUP BY status
ORDER BY total DESC;

-- 3. CEK STORE ASSIGNMENT UNTUK SATOR
-- Ini penting karena Sator hanya bisa lihat data dari store yang di-assign
SELECT 
    'Sator Store Assignments' as check_type,
    u.full_name as sator_name,
    u.id as sator_id,
    COUNT(DISTINCT sa.store_id) as assigned_stores,
    STRING_AGG(DISTINCT s.name, ', ') as store_names
FROM users u
LEFT JOIN sator_store_assignments sa ON sa.sator_id = u.id AND sa.is_active = true
LEFT JOIN stores s ON s.id = sa.store_id
WHERE u.role = 'sator'
GROUP BY u.id, u.full_name
ORDER BY u.full_name;

-- 4. CEK IMEI NORMALIZATION PER STORE
SELECT 
    'IMEI per Store' as check_type,
    s.name as store_name,
    s.id as store_id,
    COUNT(DISTINCT in2.id) as total_imei,
    COUNT(DISTINCT CASE WHEN in2.status = 'pending' THEN in2.id END) as pending,
    COUNT(DISTINCT CASE WHEN in2.status = 'approved' THEN in2.id END) as approved,
    COUNT(DISTINCT CASE WHEN in2.status = 'rejected' THEN in2.id END) as rejected,
    MAX(in2.created_at) as latest_submission
FROM stores s
LEFT JOIN imei_normalizations in2 ON in2.store_id = s.id
GROUP BY s.id, s.name
HAVING COUNT(DISTINCT in2.id) > 0
ORDER BY total_imei DESC;

-- 5. CEK RELASI PROMOTOR -> STORE -> SATOR
SELECT 
    'Promotor to Sator Chain' as check_type,
    p.full_name as promotor_name,
    s.name as store_name,
    sat.full_name as sator_name,
    COUNT(DISTINCT in2.id) as total_imei_submitted,
    COUNT(DISTINCT CASE WHEN in2.status = 'pending' THEN in2.id END) as pending_count
FROM imei_normalizations in2
JOIN users p ON p.id = in2.promotor_id
JOIN stores s ON s.id = in2.store_id
LEFT JOIN sator_store_assignments sa ON sa.store_id = s.id AND sa.is_active = true
LEFT JOIN users sat ON sat.id = sa.sator_id
GROUP BY p.full_name, s.name, sat.full_name
ORDER BY total_imei_submitted DESC;

-- 6. CEK IMEI YANG TIDAK PUNYA SATOR ASSIGNMENT
SELECT 
    'IMEI without Sator Assignment' as check_type,
    COUNT(*) as orphaned_imei,
    COUNT(DISTINCT in2.store_id) as affected_stores,
    STRING_AGG(DISTINCT s.name, ', ') as store_names
FROM imei_normalizations in2
JOIN stores s ON s.id = in2.store_id
LEFT JOIN sator_store_assignments sa ON sa.store_id = in2.store_id AND sa.is_active = true
WHERE sa.id IS NULL;

-- 7. CEK DETAIL IMEI TERBARU (10 TERAKHIR)
SELECT 
    'Latest IMEI Submissions' as check_type,
    in2.created_at,
    p.full_name as promotor,
    s.name as store,
    in2.old_imei,
    in2.new_imei,
    in2.status,
    in2.reason,
    sat.full_name as assigned_sator
FROM imei_normalizations in2
JOIN users p ON p.id = in2.promotor_id
JOIN stores s ON s.id = in2.store_id
LEFT JOIN sator_store_assignments sa ON sa.store_id = s.id AND sa.is_active = true
LEFT JOIN users sat ON sat.id = sa.sator_id
ORDER BY in2.created_at DESC
LIMIT 10;

-- 8. CEK FUNCTION GET_SATOR_TIM_DETAIL (yang dipakai di Sator Sales Tab)
-- Pastikan function ini include imei_normalizations
SELECT 
    'Function Check' as check_type,
    routine_name,
    routine_type,
    data_type as return_type
FROM information_schema.routines
WHERE routine_name LIKE '%sator%'
    AND routine_schema = 'public'
ORDER BY routine_name;

-- 9. CEK RLS POLICIES untuk imei_normalizations
SELECT 
    'RLS Policies' as check_type,
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename = 'imei_normalizations'
ORDER BY policyname;

-- 10. SIMULASI QUERY YANG DIPAKAI DI SATOR SALES TAB
-- Ganti 'SATOR_USER_ID' dengan ID Sator yang sebenarnya
DO $$
DECLARE
    test_sator_id UUID;
BEGIN
    -- Ambil sator pertama untuk test
    SELECT id INTO test_sator_id
    FROM users
    WHERE role = 'sator'
    LIMIT 1;
    
    IF test_sator_id IS NOT NULL THEN
        RAISE NOTICE 'Testing with Sator ID: %', test_sator_id;
        
        -- Simulasi query yang mungkin dipakai di app
        RAISE NOTICE 'Stores assigned to this Sator:';
        PERFORM store_id FROM sator_store_assignments 
        WHERE sator_id = test_sator_id AND is_active = true;
        
        RAISE NOTICE 'IMEI normalizations visible to this Sator:';
        PERFORM COUNT(*) FROM imei_normalizations in2
        WHERE in2.store_id IN (
            SELECT store_id FROM sator_store_assignments 
            WHERE sator_id = test_sator_id AND is_active = true
        );
    END IF;
END $$;
