# 🎯 TARGET ACHIEVEMENT SYSTEM - USER GUIDE
**Date:** 24 Januari 2026  
**Status:** Ready to Deploy

---

## 📋 OVERVIEW

System ini menghitung target achievement dengan time-gone analysis secara otomatis.

### **Features:**
✅ Target vs Actual (All Type & Fokus)
✅ Achievement % calculation
✅ Time-gone % comparison
✅ Warning system (achievement < time-gone)
✅ Fokus product detail tracking
✅ Real-time updates

---

## 🚀 HOW TO USE

### **1. Run Migration**
```bash
# Copy-paste ke Supabase SQL Editor
File: 20260124_target_achievement_system.sql
```

### **2. Get Target Dashboard (Flutter)**
```dart
// Get current period target for logged-in user
final response = await supabase.rpc('get_target_dashboard', params: {
  'p_user_id': supabase.auth.currentUser!.id,
  'p_period_id': null, // null = current period
});

final data = response[0];

print('Target: Rp ${data['target_omzet']}');
print('Actual: Rp ${data['actual_omzet']}');
print('Achievement: ${data['achievement_omzet_pct']}%');
print('Time Gone: ${data['time_gone_pct']}%');
print('Status: ${data['status_omzet']}'); // ACHIEVED, ON_TRACK, WARNING

if (data['warning_omzet']) {
  print('⚠️ WARNING: Achievement below time-gone!');
}
```

### **3. Display in UI**
```dart
// Target Card
Card(
  child: Column(
    children: [
      Text('Target All Type'),
      Text('Rp ${formatCurrency(data['target_omzet'])}'),
      Text('Actual: Rp ${formatCurrency(data['actual_omzet'])}'),
      LinearProgressIndicator(
        value: data['achievement_omzet_pct'] / 100,
        backgroundColor: Colors.grey[300],
        valueColor: AlwaysStoppedAnimation(
          data['warning_omzet'] ? Colors.red : Colors.green
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Achievement: ${data['achievement_omzet_pct']}%'),
          Text('Time: ${data['time_gone_pct']}%'),
        ],
      ),
      if (data['warning_omzet'])
        Container(
          color: Colors.red[100],
          padding: EdgeInsets.all(8),
          child: Text('⚠️ Achievement below time-gone!'),
        ),
    ],
  ),
)
```

---

## 📊 DATA STRUCTURE

### **Response Format:**
```json
{
  "period_id": "uuid",
  "period_name": "Januari 2026",
  "start_date": "2026-01-01",
  "end_date": "2026-01-31",
  
  "target_omzet": 10000000,
  "actual_omzet": 4000000,
  "achievement_omzet_pct": 40.00,
  
  "target_fokus_total": 50,
  "actual_fokus_total": 23,
  "achievement_fokus_pct": 46.00,
  
  "fokus_details": [
    {
      "bundle_id": "uuid",
      "bundle_name": "Y-Series Premium",
      "target_qty": 20,
      "actual_qty": 8,
      "achievement_pct": 40.00
    },
    {
      "bundle_id": "uuid",
      "bundle_name": "V-Series",
      "target_qty": 15,
      "actual_qty": 10,
      "achievement_pct": 66.67
    }
  ],
  
  "time_gone_pct": 48.39,
  "status_omzet": "WARNING",
  "status_fokus": "WARNING",
  "warning_omzet": true,
  "warning_fokus": true
}
```

### **Status Values:**
- `ACHIEVED`: Achievement >= 100%
- `ON_TRACK`: Achievement >= Time-gone %
- `WARNING`: Achievement < Time-gone %

---

## 🔄 AUTO-UPDATE MECHANISM

### **When does data update?**
1. **Real-time:** When promotor inputs sale
2. **Cached:** Materialized view refreshes every hour
3. **Manual:** Call `refresh_target_dashboard()` if needed

### **Refresh Schedule (Automatic):**
```sql
-- Set up cron job (if using pg_cron extension)
SELECT cron.schedule(
  'refresh-target-dashboard',
  '0 * * * *', -- Every hour
  $$SELECT refresh_target_dashboard()$$
);
```

### **Manual Refresh:**
```sql
-- Run this in SQL Editor if data seems stale
SELECT refresh_target_dashboard();
```

---

## 🎨 UI EXAMPLES

### **Example 1: Promotor Dashboard**
```
┌─────────────────────────────────────────────────────────┐
│ 🎯 TARGET JANUARI 2026                                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ALL TYPE TARGET                                         │
│ Target: Rp 10.000.000                                   │
│ Actual: Rp 4.000.000                                    │
│ [████████░░░░░░░░░░░░] 40%                              │
│ Time Gone: 48% | Status: ⚠️ WARNING                     │
│                                                         │
│ ⚠️ Achievement below time-gone! Need to speed up!      │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ FOKUS TARGET                                            │
│ Target: 50 unit                                         │
│ Actual: 23 unit                                         │
│ [█████████░░░░░░░░░░░] 46%                              │
│ Time Gone: 48% | Status: ⚠️ WARNING                     │
│                                                         │
│ Detail:                                                 │
│ ├─ Y-Series Premium: 8/20 (40%) ⚠️                     │
│ ├─ Y29 Series: 10/15 (67%) ✅                          │
│ └─ V-Series: 5/15 (33%) ⚠️                             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### **Example 2: SATOR Dashboard (Team View)**
```
┌─────────────────────────────────────────────────────────┐
│ 👥 TEAM TARGET - JANUARI 2026                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ TEAM ALL TYPE TARGET                                    │
│ Target: Rp 50.000.000                                   │
│ Actual: Rp 35.000.000                                   │
│ [██████████████░░░░░░] 70%                              │
│ Time Gone: 48% | Status: ✅ ON TRACK                    │
│                                                         │
│ Top Performers:                                         │
│ 1. Ahmad (120%) ⭐                                      │
│ 2. Budi (95%) ✅                                        │
│ 3. Citra (85%) ✅                                       │
│                                                         │
│ Need Attention:                                         │
│ - Dedi (35%) ⚠️                                         │
│ - Eka (40%) ⚠️                                          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🧪 TESTING

### **Test 1: Time-Gone Calculation**
```sql
-- Test time-gone for current period
SELECT 
    period_name,
    start_date,
    end_date,
    CURRENT_DATE as today,
    get_time_gone_percentage(id) as time_gone_pct
FROM target_periods
WHERE CURRENT_DATE BETWEEN start_date AND end_date;

-- Expected: Should show correct percentage based on days passed
```

### **Test 2: Achievement Calculation**
```sql
-- Test achievement for a user
SELECT * FROM calculate_target_achievement(
    'user-uuid-here',
    'period-uuid-here'
);

-- Expected: Should show target, actual, achievement %, status
```

### **Test 3: Warning System**
```sql
-- Get all users with warnings
SELECT 
    full_name,
    achievement_omzet_pct,
    time_gone_pct,
    status_omzet
FROM v_target_dashboard
WHERE warning_omzet = true
AND CURRENT_DATE BETWEEN start_date AND end_date;

-- Expected: Users where achievement < time-gone
```

---

## 🔧 TROUBLESHOOTING

### **Problem: Data not updating**
**Solution:**
```sql
-- Refresh materialized view
SELECT refresh_target_dashboard();
```

### **Problem: Wrong achievement percentage**
**Solution:**
```sql
-- Check if dashboard_performance_metrics is updated
SELECT * FROM dashboard_performance_metrics
WHERE user_id = 'user-uuid'
AND period_id = 'period-uuid';

-- If empty, check if sales trigger is working
```

### **Problem: Time-gone shows > 100%**
**Solution:**
```sql
-- Check if period dates are correct
SELECT * FROM target_periods WHERE id = 'period-uuid';

-- Period should not be in the past
```

---

## 📝 ADMIN TASKS

### **Set Targets (Admin UI already exists)**
```dart
// Admin sets target via admin_targets_page.dart
// System automatically uses these targets in calculations
```

### **Monitor Warnings**
```sql
-- Get summary of warnings
SELECT 
    COUNT(*) FILTER (WHERE warning_omzet) as omzet_warnings,
    COUNT(*) FILTER (WHERE warning_fokus) as fokus_warnings,
    COUNT(*) as total_users
FROM v_target_dashboard
WHERE CURRENT_DATE BETWEEN start_date AND end_date;
```

---

## ✅ SUCCESS CRITERIA

System is working correctly when:
- ✅ Target dashboard shows correct data
- ✅ Achievement % matches manual calculation
- ✅ Time-gone % is accurate
- ✅ Warnings appear when achievement < time-gone
- ✅ Fokus details show per-product breakdown
- ✅ Data updates automatically after sales

---

**Status:** Ready for deployment
**Next:** Implement Weekly Target Tracking (Phase 2)
