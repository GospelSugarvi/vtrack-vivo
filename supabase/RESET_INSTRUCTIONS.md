# 🔄 RESET TARGET PERIODS - INSTRUCTIONS

## ⚠️ WARNING
Script ini akan **MENGHAPUS SEMUA DATA TARGET** yang ada:
- Target periods
- User targets
- Fokus bundles
- Fokus targets

**Pastikan backup data jika diperlukan!**

---

## 📋 STEPS

### 1. Backup Data (Optional)
```sql
-- Backup target_periods
CREATE TABLE target_periods_backup AS SELECT * FROM target_periods;

-- Backup user_targets
CREATE TABLE user_targets_backup AS SELECT * FROM user_targets;

-- Backup fokus_bundles
CREATE TABLE fokus_bundles_backup AS SELECT * FROM fokus_bundles;

-- Backup fokus_targets
CREATE TABLE fokus_targets_backup AS SELECT * FROM fokus_targets;
```

### 2. Run Reset Script
```bash
# Copy-paste ke Supabase SQL Editor:
File: supabase/reset_target_periods.sql
```

### 3. Run Migration (if not yet)
```bash
# Copy-paste ke Supabase SQL Editor:
File: supabase/migrations/20260124_simplify_target_periods.sql
```

### 4. Create New Period
```
1. Go to Admin → Targets
2. Click "Bulan Baru"
3. Select: Bulan = Januari, Tahun = 2026
4. Click "Buat"
```

### 5. Set Targets
```
1. Select: Bulan Target = Januari 2026
2. Expand promotor card
3. Fill targets
4. Click "Simpan"
```

---

## ✅ VERIFICATION

After reset, check:
- [ ] No duplicate error when creating Januari 2026
- [ ] Time-gone shows correct % (23 Jan = 74.19%)
- [ ] Promotor dashboard shows target card
- [ ] Achievement calculation works

---

## 🔙 RESTORE (if needed)

If you need to restore backup:
```sql
-- Restore target_periods
INSERT INTO target_periods SELECT * FROM target_periods_backup;

-- Restore user_targets
INSERT INTO user_targets SELECT * FROM user_targets_backup;

-- Restore fokus_bundles
INSERT INTO fokus_bundles SELECT * FROM fokus_bundles_backup;

-- Restore fokus_targets
INSERT INTO fokus_targets SELECT * FROM fokus_targets_backup;
```

---

**Ready to reset? Run the script!**
