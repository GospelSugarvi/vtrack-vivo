# 📈 SCALABILITY STRATEGY & FUTURE-PROOFING
**Date:** 12 Januari 2026  
**Status:** LOCKED ✅

---

## 🎯 TUJUAN

Dokumen ini mendefinisikan strategi untuk:
1. Menangani pertumbuhan data
2. Menyiapkan scaling user
3. Memonitor kesehatan sistem
4. Memastikan backup & recovery

---

## 📊 CURRENT BASELINE

```
Users: 35-50 active
Platform: Supabase Free Tier
Database: PostgreSQL 500MB limit
Images: Cloudinary 25GB limit
Chat Retention: 1 bulan
```

---

## 🗄️ DATA GROWTH MANAGEMENT

### **A. Projected Data Growth**

| Data Type | Per Day | Per Month | Per Year |
|-----------|---------|-----------|----------|
| Sales transactions | 50 | 1,500 | 18,000 |
| Stock entries | 35 | 1,050 | 12,600 |
| Chat messages | 200 | 6,000 | 72,000* |
| Images | 100 | 3,000 | 36,000 |
| Bonus logs | 50 | 1,500 | 18,000 |

*Chat auto-deleted setelah 1 bulan

### **B. Storage Projections**

```
Year 1: ~20 MB database + 5 GB images
Year 2: ~40 MB database + 10 GB images
Year 3: ~60 MB database + 15 GB images
Year 5: ~100 MB database + 25 GB images

Supabase Free: 500 MB → SAFE sampai ~25 tahun
Cloudinary Free: 25 GB → FULL di tahun 5 tanpa cleanup
```

### **C. Data Archiving Strategy**

```
ARCHIVE RULES:

Sales & Stock (> 12 bulan):
├─ Move ke archive_* tables
├─ Tetap queryable (read-only)
├─ Tidak muncul di daily queries
└─ Admin bisa export ke Excel

Chat Messages (> 1 bulan):
├─ Auto-delete via pg_cron
├─ Announcement: 6 bulan retention
└─ Tidak di-archive (tidak penting)

Audit Logs (> 6 bulan):
├─ Move ke archive_audit_logs
├─ Keep for compliance
└─ Queryable by Admin only

Images (> 3 bulan):
├─ Auto-delete dari Cloudinary
├─ Keep sales/stock images longer (1 tahun)
└─ Profile photos: permanent
```

### **D. Archive Tables**

```sql
-- Archive tables (identical structure)
CREATE TABLE archive_sales AS SELECT * FROM sales WHERE 1=0;
CREATE TABLE archive_stock AS SELECT * FROM stock WHERE 1=0;
CREATE TABLE archive_audit_logs AS SELECT * FROM audit_logs WHERE 1=0;

-- Monthly archive job
CREATE OR REPLACE FUNCTION archive_old_data()
RETURNS void AS $$
BEGIN
  -- Move sales older than 12 months
  INSERT INTO archive_sales 
  SELECT * FROM sales 
  WHERE created_at < NOW() - INTERVAL '12 months';
  
  DELETE FROM sales 
  WHERE created_at < NOW() - INTERVAL '12 months';
  
  -- Similar for stock, audit_logs
END;
$$ LANGUAGE plpgsql;

-- Schedule monthly (via pg_cron or Edge Function)
```

---

## 👥 USER SCALING ROADMAP

### **Phase 1: 35-100 Users (CURRENT)**
```
Status: Free tier sufficient
Actions:
├─ Add indexes on frequently queried columns
├─ Implement connection pooling
├─ Monitor query performance
└─ Cost: $0/month
```

### **Phase 2: 100-250 Users**
```
Status: Approaching limits
Actions:
├─ Supabase Pro ($25/month) for:
│   ├─ 8 GB database
│   ├─ 100 GB storage
│   └─ Daily backups
├─ PgBouncer connection pooling
├─ Read replica for reports
└─ Split chat to separate table partition
```

### **Phase 3: 250+ Users**
```
Status: Beyond single-region
Actions:
├─ Dedicated chat service (Stream.io or Firebase)
├─ Supabase Team ($599/month) or custom
├─ Geographic distribution
├─ Separate analytics database
└─ Major architecture review needed
```

### **Scaling Triggers**

| Metric | Warning | Action Needed |
|--------|---------|---------------|
| Concurrent connections | > 150 | Enable pooling |
| Database size | > 400 MB | Archive + cleanup |
| Query latency p95 | > 500ms | Add indexes |
| Realtime connections | > 150 | Evaluate paid tier |
| Cloudinary usage | > 20 GB | Aggressive cleanup |

---

## 🔍 MONITORING & ALERTING

### **A. Admin Monitoring Dashboard**

```
SYSTEM HEALTH (Admin Panel):
┌─────────────────────────────────────────┐
│ 📊 SYSTEM STATUS                        │
├─────────────────────────────────────────┤
│                                         │
│ Database                                │
│ ├─ Size: 45 MB / 500 MB (9%)   🟢      │
│ ├─ Connections: 12 / 200       🟢      │
│ └─ Avg Query: 85ms             🟢      │
│                                         │
│ Cloudinary                              │
│ ├─ Storage: 8.5 GB / 25 GB     🟢      │
│ └─ Monthly: 15/25 credits      🟢      │
│                                         │
│ Supabase                                │
│ ├─ Edge Functions: 80K / 500K  🟢      │
│ ├─ Realtime: 35 connections    🟢      │
│ └─ Last Backup: 2 hours ago    🟢      │
│                                         │
│ ⚠️ Warnings: None                       │
└─────────────────────────────────────────┘
```

### **B. Automated Alerts**

```
ALERT RULES:

🔴 CRITICAL (Immediate action):
├─ Database > 450 MB (90%)
├─ Edge Function errors > 10/hour
├─ Backup failed
└─ Service down

🟡 WARNING (Within 24 hours):
├─ Database > 400 MB (80%)
├─ Cloudinary > 20 GB (80%)
├─ Query latency > 500ms average
└─ Realtime connections > 150

🟢 INFO (Weekly review):
├─ Monthly growth report
├─ User activity summary
└─ Cleanup job status

NOTIFICATION:
├─ Push notification ke Admin app
├─ Email backup
└─ WhatsApp webhook (critical only)
```

### **C. Implementation**

```sql
-- Monitoring function
CREATE OR REPLACE FUNCTION get_system_health()
RETURNS jsonb AS $$
DECLARE
  db_size bigint;
  result jsonb;
BEGIN
  SELECT pg_database_size(current_database()) INTO db_size;
  
  result := jsonb_build_object(
    'database_size_mb', db_size / 1024 / 1024,
    'database_limit_mb', 500,
    'database_usage_pct', (db_size / 1024 / 1024 * 100) / 500,
    'timestamp', NOW()
  );
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;
```

---

## 💾 BACKUP & RECOVERY

### **A. Backup Strategy**

```
BACKUP LAYERS:

1. SUPABASE AUTO (Free Tier):
   └─ Daily automatic backup
   └─ 7 days retention
   └─ Point-in-time recovery: ❌ (Pro only)

2. MANUAL EXPORT (Weekly):
   ├─ Admin trigger manual backup
   ├─ Export critical tables to JSON
   ├─ Download dan simpan lokal
   └─ Keep 4 weekly backups

3. CLOUDINARY (Images):
   ├─ No auto-backup
   ├─ Keep original URLs in database
   └─ Re-upload jika hilang (dari user)
```

### **B. Backup Schedule**

| Type | Frequency | Retention | Who |
|------|-----------|-----------|-----|
| Supabase auto | Daily | 7 days | Automatic |
| Manual export | Weekly | 4 weeks | Admin |
| Critical data | Before major change | Permanent | Admin |
| Cloudinary | N/A | 3 months | Auto-cleanup |

### **C. Disaster Recovery Plan**

```
SCENARIO 1: Database Corruption
├─ Detect: Query errors, data inconsistency
├─ Action: Restore from Supabase backup (< 24 hours)
├─ Recovery time: ~30 minutes
└─ Data loss: Max 24 hours

SCENARIO 2: Accidental Data Deletion
├─ Detect: User report / audit log
├─ Action: Restore specific table from backup
├─ Recovery time: ~1 hour
└─ Use: audit_log for point-in-time recovery

SCENARIO 3: Supabase Service Down
├─ Detect: App errors / status page
├─ Action: Wait for Supabase recovery
├─ Mitigation: Offline mode enabled
└─ User notified via push (if possible)

SCENARIO 4: Complete Data Loss
├─ Detect: Empty database
├─ Action: Full restore from backup
├─ Reconstruct: Cloudinary images, user configs
└─ Recovery time: 2-4 hours
```

### **D. Recovery Testing**

```
MONTHLY TEST:
├─ Export 1 table via manual backup
├─ Create test project di Supabase
├─ Import dan verify data
├─ Document result
└─ Admin sign-off

QUARTERLY TEST:
├─ Full database export
├─ Restore to staging environment
├─ Run basic app functions
├─ Verify data integrity
└─ Document dan report
```

---

## 🚀 PERFORMANCE OPTIMIZATION

### **A. Database Indexes**

```sql
-- Critical indexes (create at launch)
CREATE INDEX idx_sales_date ON sales(created_at DESC);
CREATE INDEX idx_sales_user ON sales(user_id, created_at DESC);
CREATE INDEX idx_stock_toko ON stock(toko_id, created_at DESC);
CREATE INDEX idx_chat_room ON chat_messages(room_id, created_at DESC);
CREATE INDEX idx_audit_timestamp ON audit_logs(created_at DESC);

-- Composite indexes for common queries
CREATE INDEX idx_sales_user_month ON sales(user_id, 
  DATE_TRUNC('month', created_at));
CREATE INDEX idx_target_period ON targets(period_start, period_end);
```

### **B. Query Optimization**

```
RULES:
├─ Limit all queries (max 100 rows default)
├─ Use pagination, not load-all
├─ Aggregate at database level (not app)
├─ Cache frequently accessed config
└─ Avoid SELECT * (specify columns)

ANTI-PATTERNS TO AVOID:
├─ ❌ Loading all chat history at once
├─ ❌ Calculating bonus in frontend
├─ ❌ Fetching all sales for reports
├─ ❌ Real-time subscription on large tables
└─ ❌ N+1 queries for related data
```

### **C. Caching Strategy**

```
CACHE (in-app / local storage):
├─ User profile & config: 24 hours
├─ Product list: 1 hour
├─ Toko list: 1 hour
├─ Bonus rules: 1 hour
└─ Static assets: 7 days

NO CACHE (always fresh):
├─ Sales data: real-time
├─ Stock levels: real-time
├─ Chat messages: real-time
├─ Targets: per session
└─ Achievement: per query
```

---

## 🧹 CLEANUP AUTOMATION

### **A. Scheduled Jobs**

```
DAILY (02:00 WITA):
├─ Delete expired chat messages
├─ Clean up orphaned images
└─ Update aggregation tables

WEEKLY (Sunday 03:00 WITA):
├─ Archive audit logs > 6 months
├─ Clean Cloudinary unused files
└─ Generate usage report

MONTHLY (1st, 04:00 WITA):
├─ Archive sales/stock > 12 months
├─ Full database vacuum
├─ Send capacity report to Admin
└─ Test backup restore (automated)
```

### **B. Implementation**

```sql
-- pg_cron extension (if available)
SELECT cron.schedule('cleanup-chat', '0 2 * * *', 
  'DELETE FROM chat_messages WHERE expires_at < NOW()');

-- Or via Edge Function (scheduled)
// supabase/functions/daily-cleanup/index.ts
Deno.cron("Daily Cleanup", "0 2 * * *", async () => {
  await supabase.rpc('cleanup_expired_data');
  await cloudinaryCleanup();
});
```

---

## ✅ CHECKLIST OPERASIONAL

### **Weekly Admin Tasks**
```
[ ] Review system health dashboard
[ ] Check backup status
[ ] Review error logs
[ ] Check storage usage
```

### **Monthly Admin Tasks**
```
[ ] Verify backup restore works
[ ] Review capacity projections
[ ] Archive old data if needed
[ ] Update documentation
```

### **Quarterly Admin Tasks**
```
[ ] Full disaster recovery test
[ ] Performance review
[ ] Scaling assessment
[ ] Budget review (if any)
```

---

## 📋 SUMMARY

| Aspect | Strategy | Trigger |
|--------|----------|---------|
| Data Growth | Archive > 12 months | Auto monthly |
| User Growth | Upgrade at 100+ users | Manual decision |
| Monitoring | Admin dashboard + alerts | Real-time |
| Backup | Daily auto + weekly manual | Scheduled |
| Cleanup | Chat 1mo, Images 3mo, Audit 6mo | Scheduled |
| Performance | Indexes + caching | At launch |

---

**Status:** Scalability Strategy - 100% LOCKED ✅
