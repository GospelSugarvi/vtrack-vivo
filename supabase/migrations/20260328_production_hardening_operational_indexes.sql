create index if not exists idx_hierarchy_sator_promotor_active_sator
  on public.hierarchy_sator_promotor(sator_id, promotor_id)
  where active = true;

create index if not exists idx_hierarchy_spv_sator_active_spv
  on public.hierarchy_spv_sator(spv_id, sator_id)
  where active = true;

create index if not exists idx_promotion_reports_promotor_created_at
  on public.promotion_reports(promotor_id, created_at desc);

create index if not exists idx_follower_reports_promotor_created_at
  on public.follower_reports(promotor_id, created_at desc);

create index if not exists idx_allbrand_reports_promotor_report_date
  on public.allbrand_reports(promotor_id, report_date desc);

create index if not exists idx_stock_movement_log_moved_by_moved_at
  on public.stock_movement_log(moved_by, moved_at desc);
