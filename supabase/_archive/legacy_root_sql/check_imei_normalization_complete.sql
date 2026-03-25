-- ============================================
-- CHECK: IMEI Normalization Complete Flow
-- Memeriksa seluruh alur dari Promotor ke Sator
-- ============================================

-- 1. CEK TABEL imei_normalizations
SELECT 
    '1. IMEI Normalizations Table' as step,
    COUNT(*) as total_records,
    COUNT(DISTINCT promotor_id) as unique_promotors,
    COUNT(DISTINCT store_id) as unique_stores,
    MIN(created_at) as oldest,
    MAX(created_at) as newest
FROM imei_normalizations;

-- 2. CEK STATUS BREAKDOWN
SELECT 
    '2. Status Breakdown' as step,
    status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage
FROM imei_normalizations
GROUP BY status
ORDER BY count DESC;

-- 3. CEK SATOR STORE ASSIGNMENTS
SELECT 
    '3. Sator Store Assignments' as step,
    u.full_name as sator_name,
    COUNT(DISTINCT sa.store_id) as assigned_stores,
    STRING_AGG(DISTINCT s.name, ', ' ORDER BY s.name) as stores
FROM users u
LEFT JOIN sator_store_assignments sa ON sa.sator_id = u.id AND sa.is_active = true
LEFT JOIN stores s ON s.id = sa.store_id
WHERE u.role = 'sator'
GROUP BY u.id, u.full_name
ORDER BY u.full_name;

-- 4. CEK IMEI PER STORE (dengan info Sator)
SELECT 
    '4. IMEI per Store' as step,
    s.name as store_name,
    sat.full_name as assigned_sator,
    COUNT(in2.id) as total_imei,
    COUNT(CASE WHEN in2.status = 'pending' THEN 1 END) as pending,
    COUNT(CASE WHEN in2.status = 'sent' THEN 1 END) as sent,
    COUNT(CASE WHEN in2.status = 'normal' THEN 1 END) as normal,
    COUNT(CASE WHEN in2.status = 'scanned' THEN 1 END) as scanned,
    MAX(in2.created_at) as latest_submission
FROM stores s
LEFT JOIN sator_store_assignments sa ON sa.store_id = s.id AND sa.is_active = true
LEFT JOIN users sat ON sat.id = sa.sator_id
LEFT JOIN imei_normalizations in2 ON in2.store_id = s.id
GROUP BY s.id, s.name, sat.full_name
HAVING COUNT(in2.id) > 0
ORDER BY total_imei DESC;

-- 5. CEK DETAIL IMEI TERBARU (20 terakhir)
SELECT 
    '5. Latest IMEI Submissions' as step,
    in2.created_at::date as tanggal,
    in2.created_at::time as waktu,
    p.full_name as promotor,
    s.name as store,
    sat.full_name as sator,
