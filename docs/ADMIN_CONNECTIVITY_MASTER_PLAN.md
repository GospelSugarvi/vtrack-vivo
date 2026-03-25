# 🎯 ADMIN CONNECTIVITY - MASTER PLAN
**Date:** 23 Januari 2026  
**Goal:** Make ALL admin settings work in the system automatically

---

## 📋 REQUIREMENTS (From User)

### **1. Target System with Time-Gone Analysis**
**What:**
- Show: Target, Actual, Achievement %
- Calculate: Achievement % automatically
- Compare: Time-gone vs Achievement %
- Warning: If achievement < time-gone

**Example:**
```
Period: 1-31 Januari (31 days)
Today: 15 Januari (48% time gone)

Target All Type: Rp 10.000.000
Actual: Rp 4.000.000
Achievement: 40%

Status: ⚠️ WARNING (40% < 48% time-gone)

Target Fokus: 50 unit
├─ Y400: Target 20, Actual 8 (40%)
├─ Y29: Target 15, Actual 10 (67%)
└─ V60: Target 15, Actual 5 (33%)
Total Actual: 23 unit (46%)

Status: ⚠️ WARNING (46% < 48% time-gone)
```

### **2. Weekly Target Tracking**
**What:**
- Admin sets weekly breakdown (30%, 25%, 20%, 25%)
- System calculates weekly target automatically
- Show warning if weekly target not achieved

**Example:**
```
Monthly Target: Rp 10.000.000
Week 1 (1-7): 30% = Rp 3.000.000
├─ Actual: Rp 2.500.000
└─ Status: ⚠️ WARNING (83% of week target)

Week 2 (8-14): 25% = Rp 2.500.000
├─ Actual: Rp 2.800.000
└─ Status: ✅ ACHIEVED (112%)
```

### **3. SATOR/SPV Bonus Auto-Calculation**
**What:**
- SATOR/SPV bonus calculated from admin settings
- Read from: kpi_settings, point_ranges, special_rewards
- Show in dashboard like promotor bonus

**Logic:**
```
SATOR Bonus = (KPI Score × Weights) + Point Bonus + Special Rewards

KPI Score:
├─ Sell Out All (40%): Achievement × Weight
├─ Sell Out Fokus (20%): Achievement × Weight
├─ Sell In (30%): Achievement × Weight
└─ KPI MA (10%): Manual score × Weight

Point Bonus:
├─ Sell Out: Price range → Points per unit
└─ Sell In: Price range → Points per unit

Special Rewards:
├─ Product-specific: Min-max unit → Reward
└─ Penalty: Below threshold → Deduct
```

### **4. Min Stock Alert System**
**What:**
- Compare current stock vs min stock (from admin settings)
- Show notification when stock < min
- Alert in dashboard and notification center

**Example:**
```
🔴 ALERT: Stock Kritis
├─ Y400 4/128 Black: 2 unit (min: 3)
├─ V60 8/256 Blue: 0 unit (min: 2)
└─ Action: Order recommended
```

---

## 🏗️ ARCHITECTURE DESIGN

### **Core Principle:**
```
Admin Settings (Database)
    ↓
Triggers/Functions (Auto-calculate)
    ↓
Dashboard/UI (Display results)
    ↓
Notifications (Alerts)
```

### **Key Tables:**
```
Admin Settings:
├─ bonus_rules (✅ Done)
├─ user_targets
├─ weekly_targets
├─ kpi_settings
├─ point_ranges
├─ special_rewards
├─ min_stock_settings
└─ fokus_targets

Calculated Results:
├─ dashboard_performance_metrics
├─ sator_bonus_calculations (new)
├─ spv_bonus_calculations (new)
├─ stock_alerts (new)
└─ target_warnings (new)

Notifications:
└─ notifications (new)
```

---

## 📝 IMPLEMENTATION PLAN

### **PHASE 1: Target System with Time-Gone** ⭐ PRIORITY 1
**Files to create:**
1. `20260124_target_achievement_system.sql`
   - Function: `calculate_target_achievement(user_id, period_id)`
   - Function: `get_time_gone_percentage(period_id)`
   - Function: `get_target_status(user_id, period_id)`
   - View: `v_target_dashboard`

2. Update dashboard to show:
   - Target vs Actual
   - Achievement %
   - Time-gone %
   - Warning status

**Logic:**
```sql
-- Time-gone calculation
time_gone_pct = (current_date - start_date) / (end_date - start_date) * 100

-- Achievement calculation
achievement_pct = (actual / target) * 100

-- Status
IF achievement_pct < time_gone_pct THEN 'WARNING'
ELSE IF achievement_pct >= 100 THEN 'ACHIEVED'
ELSE 'ON_TRACK'
```

### **PHASE 2: Weekly Target Tracking** ⭐ PRIORITY 2
**Files to create:**
1. `20260124_weekly_target_tracking.sql`
   - Function: `get_current_week(period_id, date)`
   - Function: `calculate_weekly_target(user_id, period_id, week_num)`
   - Function: `get_weekly_achievement(user_id, period_id, week_num)`
   - View: `v_weekly_progress`

**Logic:**
```sql
-- Get current week
week_num = CASE 
  WHEN day <= 7 THEN 1
  WHEN day <= 14 THEN 2
  WHEN day <= 22 THEN 3
  ELSE 4
END

-- Calculate weekly target
weekly_target = monthly_target * (weekly_percentage / 100)

-- Weekly achievement
weekly_actual = SUM(sales WHERE date IN week_range)
weekly_achievement_pct = (weekly_actual / weekly_target) * 100
```

### **PHASE 3: SATOR/SPV Bonus Calculation** ⭐ PRIORITY 3
**Files to create:**
1. `20260124_sator_spv_bonus_system.sql`
   - Function: `calculate_sator_bonus(sator_id, period_id)`
   - Function: `calculate_spv_bonus(spv_id, period_id)`
   - Table: `sator_bonus_calculations`
   - Table: `spv_bonus_calculations`
   - Trigger: Auto-calculate on sales insert

**Logic:**
```sql
-- SATOR Bonus
1. Calculate KPI Score:
   - Sell Out All: team_omzet / team_target * kpi_weight
   - Sell Out Fokus: team_fokus / fokus_target * kpi_weight
   - Sell In: team_sell_in / sell_in_target * kpi_weight
   - KPI MA: manual_score * kpi_weight
   Total KPI Score = SUM(all weighted scores)

2. Calculate Point Bonus:
   - For each sale: price → point_range → points
   - Total Points = SUM(all points)
   - Point Bonus = Total Points * point_value

3. Calculate Special Rewards:
   - For each product: check if unit count in range
   - If yes: add reward_amount
   - If below penalty_threshold: deduct penalty_amount

4. Total Bonus = KPI Bonus + Point Bonus + Special Rewards
```

### **PHASE 4: Min Stock Alert System** ⭐ PRIORITY 4
**Files to create:**
1. `20260124_min_stock_alert_system.sql`
   - Function: `check_min_stock_alerts()`
   - Function: `generate_stock_alerts()`
   - Table: `stock_alerts`
   - Table: `notifications`
   - Trigger: Check on stock change

**Logic:**
```sql
-- Check min stock
FOR each store_inventory:
  IF quantity < min_stock_settings.min_quantity THEN
    CREATE alert
    CREATE notification
  END IF

-- Alert levels
CRITICAL: quantity = 0
WARNING: quantity < min_quantity
OK: quantity >= min_quantity
```

---

## 🔄 INTEGRATION POINTS

### **1. Dashboard Integration**
```
Promotor Dashboard:
├─ Target Card (with time-gone)
├─ Weekly Progress Card
├─ Bonus Summary
└─ Stock Alerts (if any)

SATOR Dashboard:
├─ Team Target Card
├─ Team Weekly Progress
├─ My Bonus Calculation
├─ Team Performance
└─ Stock Alerts (all stores)

SPV Dashboard:
├─ Area Target Card
├─ Area Weekly Progress
├─ My Bonus Calculation
├─ SATOR Performance
└─ Area Stock Alerts
```

### **2. Notification Integration**
```
Notification Types:
├─ Target Warning (daily check)
├─ Weekly Target Not Met (end of week)
├─ Stock Alert (real-time)
├─ Bonus Calculated (end of period)
└─ Achievement Milestone (50%, 75%, 100%)
```

---

## 📊 SUCCESS METRICS

System is **FULLY CONNECTED** when:
- ✅ Admin changes settings → System recalculates automatically
- ✅ Dashboard shows real-time target vs actual
- ✅ Warnings appear when targets not met
- ✅ SATOR/SPV see their bonus like promotors
- ✅ Stock alerts appear when stock < min
- ✅ All calculations are database-driven
- ✅ No hardcoded business logic

---

## 🚀 EXECUTION PLAN

### **Week 1: Target & Weekly System**
- Day 1: Create target achievement functions
- Day 2: Create weekly tracking functions
- Day 3: Update dashboard UI
- Day 4: Test & fix issues
- Day 5: Deploy & monitor

### **Week 2: SATOR/SPV Bonus**
- Day 1: Design bonus calculation logic
- Day 2: Create calculation functions
- Day 3: Create dashboard for SATOR/SPV
- Day 4: Test with real data
- Day 5: Deploy & monitor

### **Week 3: Min Stock Alerts**
- Day 1: Create alert system
- Day 2: Create notification system
- Day 3: Integrate with dashboard
- Day 4: Test alerts
- Day 5: Deploy & monitor

### **Week 4: Integration & Polish**
- Day 1-2: Integration testing
- Day 3: Performance optimization
- Day 4: Documentation
- Day 5: Final deployment

---

## 📝 NOTES

**Critical Success Factors:**
1. All calculations must be in database (triggers/functions)
2. UI only displays results, never calculates
3. Admin settings must affect system immediately
4. System must be self-sustaining (no developer needed)
5. All business logic must be data-driven

**Risks:**
1. Complex calculations may slow down system
2. Real-time updates may cause performance issues
3. Notification spam if not properly throttled

**Mitigation:**
1. Use materialized views for heavy calculations
2. Cache results, refresh periodically
3. Implement notification throttling (max 1 per hour per type)

---

**Status:** Plan ready for execution
**Next:** Start with Phase 1 - Target System
