-- ==========================================================
-- CEK DATA STOCK RULES
-- ==========================================================

-- Lihat semua data stock_rules
SELECT * FROM stock_rules ORDER BY grade, product_id;

-- Lihat jumlah per grade
SELECT grade, COUNT(*) as total_products, SUM(min_qty) as total_min_qty
FROM stock_rules 
GROUP BY grade 
ORDER BY grade;
