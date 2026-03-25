-- CHECK STOK GUDANG DATA
-- Run this in SQL Editor to see if data was inserted correctly

SELECT 
    id,
    product_id,
    variant_id,
    tanggal,
    stok_gudang,
    stok_otw,
    status,
    updated_at
FROM stok_gudang_harian
ORDER BY updated_at DESC
LIMIT 10;
