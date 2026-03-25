-- =====================================================
-- DB GUARDRAIL AUDIT (Phase 2)
-- Date: 2026-03-03
-- Purpose:
-- 1) Ensure frontend-used tables/RPCs stay in sync with DB
-- 2) Ensure RLS/policy coverage does not regress
-- 3) Ensure authenticated execute grants remain available for used RPCs
-- =====================================================

WITH used_tables(name) AS (
  SELECT unnest(ARRAY[
    'activity_records','activity_types','allbrand_reports','areas',
    'assignments_promotor_store','assignments_sator_store','attendance',
    'bonus_rules','chat_members','chat_messages','chat_room_members','chat_rooms',
    'fokus_bundles','fokus_products','fokus_targets','follower_reports',
    'hierarchy_manager_spv','hierarchy_sator_promotor','hierarchy_spv_sator',
    'imei_normalizations','kpi_ma_scores','kpi_settings','message_reactions',
    'min_stock_defaults','min_stock_overrides','point_ranges','product_variants',
    'products','promotion_reports','reward_bundle_products','reward_bundles',
    'sales_sell_out','schedule_requests','schedules','shift_settings',
    'special_rewards','stock_movement_log','stock_transfer_requests',
    'stock_validation_items','stock_validations','stok','store_groups',
    'store_issues','store_visits','stores','target_periods',
    'user_quick_menu_preferences','user_targets','users','weekly_targets'
  ]::text[])
),
used_rpcs(name) AS (
  SELECT unnest(ARRAY[
    'add_comment','bulk_set_targets','copy_previous_month_schedule',
    'get_active_fokus_products','get_gudang_stock','get_leaderboard_feed',
    'get_live_feed','get_or_create_target_period','get_pending_orders',
    'get_products_for_mapping','get_promotor_bonus_details',
    'get_promotor_bonus_summary','get_promotor_schedule_detail',
    'get_reorder_recommendations','get_sale_comments','get_sator_aktivitas_tim',
    'get_sator_alerts','get_sator_daily_summary','get_sator_imei_list',
    'get_sator_kpi_detail','get_sator_kpi_summary','get_sator_live_sales',
    'get_sator_performance_per_toko','get_sator_reward_history',
    'get_sator_sales_per_promotor','get_sator_sales_per_toko',
    'get_sator_schedule_summary','get_sator_sellin_summary',
    'get_sator_sellout_summary','get_sator_tim_detail','get_sator_weekly_summary',
    'get_sellin_achievement','get_stock_summary_by_store',
    'get_store_promotor_checklist','get_store_stock_status',
    'get_target_dashboard','get_team_leaderboard','get_team_live_feed',
    'get_vivo_auto_data','initialize_default_quick_menu',
    'review_monthly_schedule','search_stock_in_area','submit_monthly_schedule',
    'toggle_reaction','update_personal_bonus_target'
  ]::text[])
)
SELECT 'SUMMARY_COUNTS' AS section,
       (SELECT count(*) FROM used_tables) AS used_tables_total,
       (SELECT count(*) FROM used_rpcs) AS used_rpcs_total;

-- 1) Missing frontend tables in public schema
WITH used_tables(name) AS (
  SELECT unnest(ARRAY[
    'activity_records','activity_types','allbrand_reports','areas',
    'assignments_promotor_store','assignments_sator_store','attendance',
    'bonus_rules','chat_members','chat_messages','chat_room_members','chat_rooms',
    'fokus_bundles','fokus_products','fokus_targets','follower_reports',
    'hierarchy_manager_spv','hierarchy_sator_promotor','hierarchy_spv_sator',
    'imei_normalizations','kpi_ma_scores','kpi_settings','message_reactions',
    'min_stock_defaults','min_stock_overrides','point_ranges','product_variants',
    'products','promotion_reports','reward_bundle_products','reward_bundles',
    'sales_sell_out','schedule_requests','schedules','shift_settings',
    'special_rewards','stock_movement_log','stock_transfer_requests',
    'stock_validation_items','stock_validations','stok','store_groups',
    'store_issues','store_visits','stores','target_periods',
    'user_quick_menu_preferences','user_targets','users','weekly_targets'
  ]::text[])
)
SELECT 'MISSING_TABLES' AS section, u.name AS object_name
FROM used_tables u
LEFT JOIN information_schema.tables t
  ON t.table_schema = 'public'
 AND t.table_name = u.name
WHERE t.table_name IS NULL
ORDER BY u.name;

-- 2) Used tables with RLS OFF
WITH used_tables(name) AS (
  SELECT unnest(ARRAY[
    'activity_records','activity_types','allbrand_reports','areas',
    'assignments_promotor_store','assignments_sator_store','attendance',
    'bonus_rules','chat_members','chat_messages','chat_room_members','chat_rooms',
    'fokus_bundles','fokus_products','fokus_targets','follower_reports',
    'hierarchy_manager_spv','hierarchy_sator_promotor','hierarchy_spv_sator',
    'imei_normalizations','kpi_ma_scores','kpi_settings','message_reactions',
    'min_stock_defaults','min_stock_overrides','point_ranges','product_variants',
    'products','promotion_reports','reward_bundle_products','reward_bundles',
    'sales_sell_out','schedule_requests','schedules','shift_settings',
    'special_rewards','stock_movement_log','stock_transfer_requests',
    'stock_validation_items','stock_validations','stok','store_groups',
    'store_issues','store_visits','stores','target_periods',
    'user_quick_menu_preferences','user_targets','users','weekly_targets'
  ]::text[])
)
SELECT 'RLS_OFF_TABLES' AS section, c.relname AS object_name
FROM used_tables u
JOIN pg_class c ON c.relname = u.name AND c.relkind = 'r'
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE NOT c.relrowsecurity
ORDER BY c.relname;

-- 3) Used tables with zero policies
WITH used_tables(name) AS (
  SELECT unnest(ARRAY[
    'activity_records','activity_types','allbrand_reports','areas',
    'assignments_promotor_store','assignments_sator_store','attendance',
    'bonus_rules','chat_members','chat_messages','chat_room_members','chat_rooms',
    'fokus_bundles','fokus_products','fokus_targets','follower_reports',
    'hierarchy_manager_spv','hierarchy_sator_promotor','hierarchy_spv_sator',
    'imei_normalizations','kpi_ma_scores','kpi_settings','message_reactions',
    'min_stock_defaults','min_stock_overrides','point_ranges','product_variants',
    'products','promotion_reports','reward_bundle_products','reward_bundles',
    'sales_sell_out','schedule_requests','schedules','shift_settings',
    'special_rewards','stock_movement_log','stock_transfer_requests',
    'stock_validation_items','stock_validations','stok','store_groups',
    'store_issues','store_visits','stores','target_periods',
    'user_quick_menu_preferences','user_targets','users','weekly_targets'
  ]::text[])
),
pc AS (
  SELECT tablename, count(*)::int AS cnt
  FROM pg_policies
  WHERE schemaname = 'public'
  GROUP BY tablename
)
SELECT 'ZERO_POLICY_TABLES' AS section, u.name AS object_name
FROM used_tables u
LEFT JOIN pc ON pc.tablename = u.name
WHERE COALESCE(pc.cnt, 0) = 0
ORDER BY u.name;

-- 4) Missing frontend RPCs
WITH used_rpcs(name) AS (
  SELECT unnest(ARRAY[
    'add_comment','bulk_set_targets','copy_previous_month_schedule',
    'get_active_fokus_products','get_gudang_stock','get_leaderboard_feed',
    'get_live_feed','get_or_create_target_period','get_pending_orders',
    'get_products_for_mapping','get_promotor_bonus_details',
    'get_promotor_bonus_summary','get_promotor_schedule_detail',
    'get_reorder_recommendations','get_sale_comments','get_sator_aktivitas_tim',
    'get_sator_alerts','get_sator_daily_summary','get_sator_imei_list',
    'get_sator_kpi_detail','get_sator_kpi_summary','get_sator_live_sales',
    'get_sator_performance_per_toko','get_sator_reward_history',
    'get_sator_sales_per_promotor','get_sator_sales_per_toko',
    'get_sator_schedule_summary','get_sator_sellin_summary',
    'get_sator_sellout_summary','get_sator_tim_detail','get_sator_weekly_summary',
    'get_sellin_achievement','get_stock_summary_by_store',
    'get_store_promotor_checklist','get_store_stock_status',
    'get_target_dashboard','get_team_leaderboard','get_team_live_feed',
    'get_vivo_auto_data','initialize_default_quick_menu',
    'review_monthly_schedule','search_stock_in_area','submit_monthly_schedule',
    'toggle_reaction','update_personal_bonus_target'
  ]::text[])
)
SELECT 'MISSING_RPCS' AS section, u.name AS object_name
FROM used_rpcs u
LEFT JOIN pg_proc p ON p.proname = u.name
LEFT JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE p.oid IS NULL
ORDER BY u.name;

-- 5) Used RPC signatures without EXECUTE grant for authenticated
WITH used_rpcs(name) AS (
  SELECT unnest(ARRAY[
    'add_comment','bulk_set_targets','copy_previous_month_schedule',
    'get_active_fokus_products','get_gudang_stock','get_leaderboard_feed',
    'get_live_feed','get_or_create_target_period','get_pending_orders',
    'get_products_for_mapping','get_promotor_bonus_details',
    'get_promotor_bonus_summary','get_promotor_schedule_detail',
    'get_reorder_recommendations','get_sale_comments','get_sator_aktivitas_tim',
    'get_sator_alerts','get_sator_daily_summary','get_sator_imei_list',
    'get_sator_kpi_detail','get_sator_kpi_summary','get_sator_live_sales',
    'get_sator_performance_per_toko','get_sator_reward_history',
    'get_sator_sales_per_promotor','get_sator_sales_per_toko',
    'get_sator_schedule_summary','get_sator_sellin_summary',
    'get_sator_sellout_summary','get_sator_tim_detail','get_sator_weekly_summary',
    'get_sellin_achievement','get_stock_summary_by_store',
    'get_store_promotor_checklist','get_store_stock_status',
    'get_target_dashboard','get_team_leaderboard','get_team_live_feed',
    'get_vivo_auto_data','initialize_default_quick_menu',
    'review_monthly_schedule','search_stock_in_area','submit_monthly_schedule',
    'toggle_reaction','update_personal_bonus_target'
  ]::text[])
)
SELECT 'RPC_NO_AUTH_EXECUTE' AS section, p.oid::regprocedure::text AS object_name
FROM used_rpcs u
JOIN pg_proc p ON p.proname = u.name
JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
WHERE NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
ORDER BY object_name;
