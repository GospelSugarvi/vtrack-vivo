-- Cek simple apakah ada stok yang available (belum terjual) di database
SELECT 
    p.model_name,
    pv.ram_rom,
    pv.color,
    s.store_id,
    st.store_name,
    COUNT(*) as qty
FROM stok s
JOIN products p ON s.product_id = p.id
JOIN product_variants pv ON s.variant_id = pv.id
JOIN stores st ON s.store_id = st.id
WHERE s.is_sold = false 
GROUP BY p.model_name, pv.ram_rom, pv.color, s.store_id, st.store_name
LIMIT 20;
