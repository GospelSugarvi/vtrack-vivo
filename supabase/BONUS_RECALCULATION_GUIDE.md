# 🔄 Bonus Recalculation Guide

## 📋 Overview
Setelah mengupdate trigger bonus calculation dari hardcoded (5000) ke database-driven (bonus_rules), data penjualan lama masih memiliki bonus lama. Guide ini untuk recalculate semua data existing.

---

## ⚠️ IMPORTANT: Run in Order!

### **Step 1: Update Trigger (WAJIB DULUAN)**
File: `20260123_fix_bonus_calculation_trigger.sql`

```sql
-- Copy-paste ke Supabase SQL Editor
-- File ini mengupdate trigger agar baca dari bonus_rules table
```

**Verify:** Coba input penjualan baru, bonus harus sesuai admin settings.

---

### **Step 2: Recalculate Existing Sales Bonus**
File: `recalculate_existing_bonus.sql`

**Apa yang dilakukan:**
- Loop semua data di `sales_sell_out`
- Hitung ulang bonus berdasarkan `bonus_rules` table
- Update kolom `estimated_bonus`

**Cara run:**
1. Buka Supabase Dashboard → SQL Editor
2. Copy-paste isi file `recalculate_existing_bonus.sql`
3. Klik **RUN**
4. Tunggu sampai selesai (akan muncul notice: "Updated X sales records")

**Expected output:**
```
NOTICE: Updated 150 sales records with recalculated bonus

total_sales | total_bonus | avg_bonus | min_bonus | max_bonus
------------|-------------|-----------|-----------|----------
    150     | 3,750,000   |  25,000   |     0     |  90,000
```

---

### **Step 3: Verify Recalculation Results**
File: `recalculate_dashboard_metrics.sql`

**Apa yang dilakukan:**
- Show bonus distribution (berapa sales di range berapa)
- Show top earners dengan bonus baru
- Show bonus by product
- Overall summary
- Check if any sales still have old bonus (5000)

**Cara run:**
1. Buka Supabase Dashboard → SQL Editor
2. Copy-paste isi file `recalculate_dashboard_metrics.sql`
3. Klik **RUN**
4. Cek hasil di output

**Expected output:**
```
bonus_range  | sales_count | total_bonus
-------------|-------------|------------
< 25k        |     50      |   625,000
25k - 50k    |     80      | 2,800,000
50k - 100k   |     20      | 1,350,000

full_name        | total_sales | total_bonus | avg_bonus_per_sale
-----------------|-------------|-------------|-------------------
YOHANIS TIPNONI  |      5      |   125,000   |      25,000
Ahmad Farhan     |      3      |    90,000   |      30,000
...
```

---

## ✅ Verification Checklist

Setelah run semua script, verify:

### **1. Check Sales Bonus**
```sql
SELECT 
  s.id,
  p.model_name,
  s.price_at_transaction,
  s.estimated_bonus,
  u.full_name,
  u.promotor_type
FROM sales_sell_out s
JOIN product_variants pv ON s.variant_id = pv.id
JOIN products p ON pv.product_id = p.id
JOIN users u ON s.promotor_id = u.id
ORDER BY s.created_at DESC
LIMIT 10;
```

**Expected:**
- Bonus bervariasi (tidak semua 5000)
- Bonus sesuai dengan harga (range-based)
- Official vs Training berbeda

### **2. Check Leaderboard**
```sql
SELECT 
  u.full_name,
  SUM(s.estimated_bonus) as daily_bonus,
  COUNT(*) as sales_count
FROM sales_sell_out s
JOIN users u ON s.promotor_id = u.id
WHERE DATE(s.transaction_date) = CURRENT_DATE
GROUP BY u.id, u.full_name
ORDER BY daily_bonus DESC;
```

**Expected:**
- Ranking berubah (karena bonus recalculated)
- Total bonus lebih akurat

### **3. Check Dashboard Metrics**
```sql
-- Total bonus per promotor (current period)
SELECT 
  u.full_name,
  COUNT(s.id) as total_sales,
  SUM(s.estimated_bonus) as total_bonus
FROM sales_sell_out s
JOIN users u ON s.promotor_id = u.id
WHERE s.transaction_date >= (SELECT start_date FROM target_periods ORDER BY start_date DESC LIMIT 1)
GROUP BY u.id, u.full_name
ORDER BY total_bonus DESC;
```

**Expected:**
- Total bonus accurate (sum of all sales bonus)

---

## 🔧 Troubleshooting

### **Problem: "Updated 0 sales records"**
**Cause:** Tidak ada data di `sales_sell_out`
**Solution:** Normal jika belum ada penjualan

### **Problem: Bonus masih 5000 semua**
**Cause:** `bonus_rules` table kosong atau tidak ada matching rule
**Solution:** 
1. Cek `bonus_rules` table: `SELECT * FROM bonus_rules;`
2. Pastikan ada range yang cover harga produk
3. Atau tambah via Admin Bonus Page

### **Problem: Some bonus = 0**
**Cause:** Harga produk tidak match dengan range di `bonus_rules`
**Solution:** 
1. Cek harga produk: `SELECT price_at_transaction FROM sales_sell_out WHERE estimated_bonus = 0;`
2. Tambah range di Admin Bonus Page untuk harga tersebut

---

## 📊 Before vs After Comparison

### **Before (Hardcoded):**
```
All sales: bonus = 5000
- Y400 (3.2jt) = 5000 ❌
- Y29 (2.5jt) = 5000 ❌
- V60 (4.5jt) = 5000 ❌
```

### **After (Database-driven):**
```
Based on bonus_rules:
- Y400 (3.2jt) = 45,000 ✅ (range 3-4jt)
- Y29 (2.5jt) = 25,000 ✅ (range 2-3jt)
- V60 (4.5jt) = 45,000 ✅ (range 4-6jt)
```

---

## 🎯 Summary

**Files to run (in order):**
1. ✅ `20260123_fix_bonus_calculation_trigger.sql` - Update trigger
2. ✅ `recalculate_existing_bonus.sql` - Fix old data
3. ✅ `recalculate_dashboard_metrics.sql` - Fix aggregations

**Result:**
- ✅ New sales: Bonus calculated from `bonus_rules`
- ✅ Old sales: Bonus recalculated from `bonus_rules`
- ✅ Dashboard: Metrics updated
- ✅ Leaderboard: Rankings accurate
- ✅ Admin: Can change bonus rules anytime

**Time required:** ~5 minutes total

---

## 🚀 Next Steps

After recalculation:
1. Test input penjualan baru → bonus harus sesuai admin settings
2. Ubah bonus di Admin Bonus Page → penjualan baru harus ikut berubah
3. Monitor leaderboard → ranking harus akurat
4. Check bonus detail page → total bonus harus benar

**Done!** Sistem sekarang 100% admin-controlled! 🎉
