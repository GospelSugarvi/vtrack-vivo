# Catatan Perbaikan Syntax Error

## Error yang Diperbaiki

### 1. FetchOptions Error
**Error:**
```
Error: Not a constant expression.
.select('id', const FetchOptions(count: CountOption.exact, head: true))
```

**Penyebab:** 
- Syntax `FetchOptions` tidak didukung di versi Supabase Flutter yang digunakan
- Method `.not()` tidak tersedia di versi ini

**Solusi:**
Menggunakan pendekatan client-side filtering:
```dart
// SEBELUM (Error):
var query = Supabase.instance.client
    .from('sales_sell_out')
    .select('id', const FetchOptions(count: CountOption.exact, head: true))
    .eq('promotor_id', userId);

if (reportedImeiList.isNotEmpty) {
  query = query.not('serial_imei', 'in', '(${reportedImeiList.join(',')})');
}

// SESUDAH (Fixed):
final allSales = await Supabase.instance.client
    .from('sales_sell_out')
    .select('serial_imei')
    .eq('promotor_id', userId);

count = allSales.where((sale) => 
  !reportedImeiList.contains(sale['serial_imei'])
).length;
```

### 2. Method .not