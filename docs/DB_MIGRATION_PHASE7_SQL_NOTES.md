# DB Migration Phase 7 SQL Notes

File:

- `supabase/PHASE7_DAILY_TARGET_DASHBOARD.sql`

## Purpose

Menambahkan function harian resmi untuk dashboard target promotor.

Function baru:

- `public.get_daily_target_dashboard(p_user_id uuid, p_date date default current_date)`

## Business Rules Locked

- target weekly bersumber dari `weekly_targets`
- weekly target ditentukan admin
- jika admin mengubah persentase mingguan, weekly dan daily ikut berubah
- weekly target bersifat `fixed`
- `no carry-over`
- target harian = target minggu aktif / `6 hari kerja`
- semua perhitungan dipisah antara:
  - `all type`
  - `produk fokus`

## Source Data Used

- `target_periods`
- `weekly_targets`
- `user_targets`
- `sales_sell_out`
- `product_variants`
- `products`

## Output Fields

- `period_id`
- `period_name`
- `active_week_number`
- `active_week_start`
- `active_week_end`
- `working_days`
- `target_weekly_all_type`
- `actual_weekly_all_type`
- `achievement_weekly_all_type_pct`
- `target_daily_all_type`
- `actual_daily_all_type`
- `achievement_daily_all_type_pct`
- `target_weekly_focus`
- `actual_weekly_focus`
- `achievement_weekly_focus_pct`
- `target_daily_focus`
- `actual_daily_focus`
- `achievement_daily_focus_pct`

## Important Notes

- actual all type mengecualikan `chip sale`
- actual focus menghitung penjualan hari/minggu aktif untuk produk dengan `products.is_focus = true`
- target harian fokus disimpan sebagai `numeric`, karena hasil pembagian mingguan `/ 6` tidak selalu bulat
- function ini belum otomatis dipakai oleh Flutter UI sampai layar target/dashboard dicutover

## Verification Query

```sql
select *
from public.get_daily_target_dashboard(
  '<promotor_user_id>'::uuid,
  current_date
);
```

## Expected Behavior

- minggu aktif ditentukan dari `weekly_targets` + tanggal periode aktif
- target weekly mengikuti persentase yang diset admin
- target harian berubah otomatis jika admin mengubah weekly distribution
- kekurangan minggu lalu tidak menambah target minggu sekarang
