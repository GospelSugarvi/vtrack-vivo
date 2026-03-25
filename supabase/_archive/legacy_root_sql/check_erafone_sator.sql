SELECT 
    st.store_name,
    p.full_name as promotor_name,
    sator.full_name as sator_name,
    hsp.active as sator_active,
    aps.active as store_active
FROM stores st
-- Cari promotor yg pegang toko ini
LEFT JOIN assignments_promotor_store aps ON st.id = aps.store_id
LEFT JOIN users p ON aps.promotor_id = p.id
-- Cari sator dari promotor tsb
LEFT JOIN hierarchy_sator_promotor hsp ON p.id = hsp.promotor_id
LEFT JOIN users sator ON hsp.sator_id = sator.id
WHERE st.store_name ILIKE '%ERAFONE%';
