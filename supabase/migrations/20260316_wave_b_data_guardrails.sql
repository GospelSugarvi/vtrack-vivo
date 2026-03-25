create unique index if not exists uq_assignments_promotor_store_active
on public.assignments_promotor_store (promotor_id)
where active = true;

create unique index if not exists uq_hierarchy_sator_promotor_active
on public.hierarchy_sator_promotor (promotor_id)
where active = true;

create unique index if not exists uq_hierarchy_spv_sator_active
on public.hierarchy_spv_sator (sator_id)
where active = true;

create unique index if not exists uq_stock_chip_requests_pending
on public.stock_chip_requests (stok_id)
where status = 'pending';

create unique index if not exists uq_stock_validations_completed_daily
on public.stock_validations (promotor_id, store_id, validation_date)
where status = 'completed';

create unique index if not exists uq_stok_unsold_imei
on public.stok (imei)
where is_sold = false;
