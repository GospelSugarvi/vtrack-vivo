-- PRE-PRODUCTION CLEANUP (OPERATIONAL / DEVELOPMENT DATA)
-- Project: ytslgrlieofvvfstwqfk
-- Date: 2026-04-15
--
-- Tujuan:
-- - Menghapus data operasional/testing sebelum go-live produksi
-- - MENJAGA data master & konfigurasi inti tetap aman
--
-- Data master yang dipertahankan (tidak dihapus):
-- - users, stores, products, product_variants
-- - hierarchy_* / assignments_*
-- - bonus_rules, point_ranges, kpi_settings
-- - stock_rules, store_groups, shift_settings
-- - special_reward_configs, kpi_metric_templates, kpi_period_settings
--
-- Catatan penting:
-- - Jalankan saat aplikasi maintenance mode / user logout semua.
-- - Gunakan service role / SQL editor owner.
-- - Skrip memakai TRUNCATE ... CASCADE agar relasi FK aman.

begin;

-- 1) CHAT & FEED
truncate table
  public.message_reactions,
  public.message_reads,
  public.chat_messages,
  public.chat_members,
  public.chat_room_members,
  public.chat_rooms,
  public.chat_report_submissions,
  public.chat_report_requests,
  public.feed_reactions,
  public.feed_comments,
  public.feed_posts,
  public.activity_feed,
  public.ai_sales_comment_jobs,
  public.ai_feed_comment_reply_jobs
restart identity cascade;

-- 2) SALES, BONUS, LEADERBOARD DERIVED
truncate table
  public.sales_sell_out_status_history,
  public.sales_bonus_events,
  public.sales_sell_out,
  public.sales_sell_in,
  public.sell_out_void_requests,
  public.sell_in_order_status_history,
  public.sell_in_order_items,
  public.sell_in_orders,
  public.sell_in,
  public.orders,
  public.order_items,
  public.dashboard_performance_metrics
restart identity cascade;

-- 3) STOCK & WAREHOUSE OPERATIONAL
truncate table
  public.stock_movement_log,
  public.stock_daily_snapshot,
  public.stock_transfer_items,
  public.stock_transfer_requests,
  public.stock_chip_request_history,
  public.stock_chip_requests,
  public.stock_validation_items,
  public.stock_validations,
  public.stok,
  public.store_inventory,
  public.stok_gudang_harian,
  public.warehouse_stock_daily,
  public.warehouse_stock,
  public.warehouse_import_run_items,
  public.warehouse_import_runs
restart identity cascade;

-- 4) ATTENDANCE / SCHEDULE / VISITING / REPORT
truncate table
  public.schedule_review_comments,
  public.schedule_requests,
  public.schedules,
  public.attendance,
  public.store_visit_comments,
  public.store_visits,
  public.permission_requests,
  public.imei_normalization_comments,
  public.imei_normalizations,
  public.imei_normalization,
  public.imei_records,
  public.report_promosi,
  public.report_follower,
  public.report_allbrand,
  public.report_vast,
  public.promotion_reports,
  public.follower_reports,
  public.allbrand_reports
restart identity cascade;

-- 5) KPI OPERASIONAL (TARGET TETAP DIPERTAHANKAN)
truncate table
  public.vast_application_evidences,
  public.vast_applications,
  public.vast_closings,
  public.vast_reminders,
  public.vast_fraud_signal_items,
  public.vast_fraud_signals,
  public.vast_alerts,
  public.vast_agg_daily_promotor,
  public.vast_agg_weekly_promotor,
  public.vast_agg_monthly_promotor,
  public.vast_agg_daily_sator,
  public.vast_agg_weekly_sator,
  public.vast_agg_monthly_sator,
  public.vast_agg_daily_spv,
  public.vast_agg_weekly_spv,
  public.vast_agg_monthly_spv,
  public.sator_monthly_kpi,
  public.sator_rewards
restart identity cascade;

-- 6) NOTIFICATIONS & APP RUNTIME FOOTPRINT
truncate table
  public.notification_deliveries,
  public.app_notifications,
  public.user_device_tokens,
  public.notification_preferences,
  public.activity_logs,
  public.audit_logs,
  public.error_logs,
  public.job_runs,
  public.idempotency_keys,
  public.rule_snapshots,
  public.recalc_requests
restart identity cascade;

commit;

-- Quick post-check (manual run if needed):
-- select
--   (select count(*) from public.sales_sell_out) as sales_sell_out_rows,
--   (select count(*) from public.chat_messages) as chat_messages_rows,
--   (select count(*) from public.stok) as stok_rows,
--   (select count(*) from public.warehouse_stock_daily) as warehouse_stock_daily_rows,
--   (select count(*) from public.schedules) as schedules_rows,
--   (select count(*) from public.app_notifications) as app_notifications_rows;
