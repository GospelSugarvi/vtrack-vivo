-- Cek status User, Assignment Toko, dan Hierarki SATOR
SELECT 
    u.email,
    u.full_name,
    u.role,
    
    -- Cek Assignment Toko
    aps.store_id,
    st.store_name,
    aps.active as store_active,
    
    -- Cek Relasi SATOR
    hsp.sator_id,
    hsp.active as sator_rel_active,
    sator_user.full_name as sator_name

FROM users u
LEFT JOIN assignments_promotor_store aps ON u.id = aps.promotor_id
LEFT JOIN stores st ON aps.store_id = st.id
LEFT JOIN hierarchy_sator_promotor hsp ON u.id = hsp.promotor_id
LEFT JOIN users sator_user ON hsp.sator_id = sator_user.id
WHERE u.email = 'masukkan_email_anda_disini@gmail.com'; 

-- NOTE: Ganti 'masukkan_email_anda_disini@gmail.com' dengan email login Anda sebelum run.
-- Atau hapus WHERE clause untuk melihat semua promotor.
