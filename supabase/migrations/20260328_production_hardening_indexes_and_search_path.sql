create or replace function public.get_sator_home_snapshot(p_sator_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_profile jsonb := '{}'::jsonb;
  v_summary jsonb := '{}'::jsonb;
  v_promotor_cards jsonb := '{}'::jsonb;
  v_period_id uuid;
  v_focus_products jsonb := '[]'::jsonb;
  v_today date := current_date;
  v_month_key date := date_trunc('month', current_date)::date;
  v_week_start date := (date_trunc('week', current_date))::date;
  v_vast_daily jsonb := '{}'::jsonb;
  v_vast_weekly jsonb := '{}'::jsonb;
  v_vast_monthly jsonb := '{}'::jsonb;
begin
  select jsonb_build_object(
    'nickname', nullif(trim(coalesce(u.nickname, '')), ''),
    'full_name', coalesce(u.full_name, 'SATOR'),
    'area', coalesce(u.area, '-'),
    'role', 'SATOR'
  )
  into v_profile
  from public.users u
  where u.id = p_sator_id;

  v_summary := coalesce(public.get_sator_home_summary(p_sator_id)::jsonb, '{}'::jsonb);
  v_promotor_cards := coalesce(public.get_sator_home_promotor_cards(p_sator_id)::jsonb, '{}'::jsonb);

  v_period_id := nullif(coalesce(v_summary #>> '{period,id}', ''), '')::uuid;

  if v_period_id is not null then
    select coalesce(jsonb_agg(to_jsonb(fp)), '[]'::jsonb)
    into v_focus_products
    from public.get_fokus_products_by_period(v_period_id) fp;
  end if;

  select to_jsonb(vd.*)
  into v_vast_daily
  from public.vast_agg_daily_sator vd
  where vd.sator_id = p_sator_id
    and vd.metric_date = v_today
  limit 1;

  select to_jsonb(vw.*)
  into v_vast_weekly
  from public.vast_agg_weekly_sator vw
  where vw.sator_id = p_sator_id
    and vw.week_start_date = v_week_start
  limit 1;

  select to_jsonb(vm.*)
  into v_vast_monthly
  from public.vast_agg_monthly_sator vm
  where vm.sator_id = p_sator_id
    and vm.month_key = v_month_key
  limit 1;

  return jsonb_build_object(
    'profile', v_profile,
    'period', coalesce(v_summary -> 'period', '{}'::jsonb),
    'counts', coalesce(v_summary -> 'counts', '{}'::jsonb),
    'daily', coalesce(v_summary -> 'daily', '{}'::jsonb),
    'weekly', coalesce(v_summary -> 'weekly', '{}'::jsonb),
    'monthly', coalesce(v_summary -> 'monthly', '{}'::jsonb),
    'agenda', coalesce(v_summary -> 'agenda', '[]'::jsonb),
    'daily_promotors', coalesce(v_promotor_cards -> 'daily', '[]'::jsonb),
    'weekly_promotors', coalesce(v_promotor_cards -> 'weekly', '[]'::jsonb),
    'monthly_promotors', coalesce(v_promotor_cards -> 'monthly', '[]'::jsonb),
    'focus_products', v_focus_products,
    'vast_daily', coalesce(v_vast_daily, '{}'::jsonb),
    'vast_weekly', coalesce(v_vast_weekly, '{}'::jsonb),
    'vast_monthly', coalesce(v_vast_monthly, '{}'::jsonb)
  );
end;
$function$;

create index if not exists idx_assignments_promotor_store_store_id
  on public.assignments_promotor_store(store_id);

create index if not exists idx_follower_reports_store_id
  on public.follower_reports(store_id);

create index if not exists idx_imei_normalizations_sator
  on public.imei_normalizations(sator_id);

create index if not exists idx_imei_normalizations_variant
  on public.imei_normalizations(variant_id);

create index if not exists idx_app_notifications_actor_user_id
  on public.app_notifications(actor_user_id);

drop index if exists public.idx_attendance_user_date_nonuniq;
drop index if exists public.idx_chat_messages_created_at;
drop index if exists public.idx_chat_messages_room_id;
drop index if exists public.idx_dashboard_metrics_user_period;
drop index if exists public.idx_user_targets_user_period;
drop index if exists public.idx_weekly_targets_period;
