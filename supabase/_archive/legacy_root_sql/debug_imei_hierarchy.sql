-- Debug: Check if the IMEI was inserted and what the hierarchy looks like
SELECT 
    n.id, 
    n.imei, 
    n.promotor_id, 
    u.full_name as promotor_name,
    n.status,
    n.created_at
FROM imei_normalizations n
JOIN users u ON n.promotor_id = u.id
ORDER BY n.created_at DESC
LIMIT 5;

-- Check hierarchy for Andhika (81d0ba59-c72e-45a6-ac7d-8045b3ccef09)
SELECT 
    h.sator_id, 
    s.full_name as sator_name,
    h.promotor_id,
    p.full_name as promotor_name,
    h.active
FROM hierarchy_sator_promotor h
JOIN users s ON h.sator_id = s.id
JOIN users p ON h.promotor_id = p.id
WHERE h.promotor_id = '81d0ba59-c72e-45a6-ac7d-8045b3ccef09';
