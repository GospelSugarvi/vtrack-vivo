-- 1. Lihat 20 produk pertama (Semua Kolom) untuk mengecek struktur data
SELECT * FROM products LIMIT 20;

-- 2. Cek apakah ada produk yang sudah diset sebagai '5G'
SELECT name, network_type, status 
FROM products 
WHERE network_type = '5G'
ORDER BY name;

-- 3. Cek varian produk dan harganya
SELECT p.name, v.ram_storage, v.price, p.network_type
FROM products p
JOIN product_variants v ON p.id = v.product_id
ORDER BY p.name;
