create or replace function public.get_sator_home_promotor_cards(p_sator_id uuid)
returns json
language sql
security definer
set search_path to 'public'
as $function$
with promotor_ids as (
  select hsp.promotor_id
  from public.hierarchy_sator_promotor hsp
  where hsp.sator_id = p_sator_id
    and hsp.active = true
),
promotor_base as (
  select
    u.id as promotor_id,
    u.full_name,
    nullif(trim(coalesce(u.nickname, '')), '') as nickname,
    coalesce(ps.store_name, '-') as store_name
  from public.users u
  join promotor_ids pi on pi.promotor_id = u.id
  left join lateral (
    select st.store_name
    from public.assignments_promotor_store aps
    join public.stores st on st.id = aps.store_id
    where aps.promotor_id = u.id
      and aps.active = true
    order by aps.created_at desc
    limit 1
  ) ps on true
),
daily_rows as (
  select
    pb.promotor_id,
    pb.full_name,
    pb.nickname,
    pb.store_name,
    d.target_daily_all_type as target_nominal,
    d.actual_daily_all_type as actual_nominal,
    d.target_daily_focus as target_focus_units,
    d.actual_daily_focus as actual_focus_units,
    d.achievement_daily_all_type_pct as achievement_pct
  from promotor_base pb
  left join lateral (
    select * from public.get_daily_target_dashboard(pb.promotor_id, current_date)
  ) d on true
),
weekly_rows as (
  select
    pb.promotor_id,
    pb.full_name,
    pb.nickname,
    pb.store_name,
    d.target_weekly_all_type as target_nominal,
    d.actual_weekly_all_type as actual_nominal,
    d.target_weekly_focus as target_focus_units,
    d.actual_weekly_focus as actual_focus_units,
    d.achievement_weekly_all_type_pct as achievement_pct
  from promotor_base pb
  left join lateral (
    select * from public.get_daily_target_dashboard(pb.promotor_id, current_date)
  ) d on true
),
monthly_rows as (
  select
    pb.promotor_id,
    pb.full_name,
    pb.nickname,
    pb.store_name,
    m.target_omzet as target_nominal,
    m.actual_omzet as actual_nominal,
    m.target_fokus_total as target_focus_units,
    m.actual_fokus_total as actual_focus_units,
    m.achievement_omzet_pct as achievement_pct
  from promotor_base pb
  left join lateral (
    select * from public.get_target_dashboard(pb.promotor_id, null)
  ) m on true
)
select json_build_object(
  'daily', coalesce((
    select json_agg(json_build_object(
      'id', dr.promotor_id,
      'name', coalesce(dr.nickname, dr.full_name),
      'nickname', dr.nickname,
      'full_name', dr.full_name,
      'store_name', dr.store_name,
      'target_nominal', coalesce(dr.target_nominal, 0),
      'actual_nominal', coalesce(dr.actual_nominal, 0),
      'target_focus_units', coalesce(dr.target_focus_units, 0),
      'actual_focus_units', coalesce(dr.actual_focus_units, 0),
      'achievement_pct', coalesce(dr.achievement_pct, 0),
      'underperform', coalesce(dr.achievement_pct, 0) > 0 and coalesce(dr.achievement_pct, 0) < 100
    ) order by coalesce(dr.target_nominal, 0) desc, coalesce(dr.nickname, dr.full_name))
    from daily_rows dr
  ), '[]'::json),
  'weekly', coalesce((
    select json_agg(json_build_object(
      'id', wr.promotor_id,
      'name', coalesce(wr.nickname, wr.full_name),
      'nickname', wr.nickname,
      'full_name', wr.full_name,
      'store_name', wr.store_name,
      'target_nominal', coalesce(wr.target_nominal, 0),
      'actual_nominal', coalesce(wr.actual_nominal, 0),
      'target_focus_units', coalesce(wr.target_focus_units, 0),
      'actual_focus_units', coalesce(wr.actual_focus_units, 0),
      'achievement_pct', coalesce(wr.achievement_pct, 0),
      'underperform', coalesce(wr.achievement_pct, 0) > 0 and coalesce(wr.achievement_pct, 0) < 100
    ) order by coalesce(wr.actual_nominal, 0) desc, coalesce(wr.nickname, wr.full_name))
    from weekly_rows wr
  ), '[]'::json),
  'monthly', coalesce((
    select json_agg(json_build_object(
      'id', mr.promotor_id,
      'name', coalesce(mr.nickname, mr.full_name),
      'nickname', mr.nickname,
      'full_name', mr.full_name,
      'store_name', mr.store_name,
      'target_nominal', coalesce(mr.target_nominal, 0),
      'actual_nominal', coalesce(mr.actual_nominal, 0),
      'target_focus_units', coalesce(mr.target_focus_units, 0),
      'actual_focus_units', coalesce(mr.actual_focus_units, 0),
      'achievement_pct', coalesce(mr.achievement_pct, 0),
      'underperform', coalesce(mr.achievement_pct, 0) > 0 and coalesce(mr.achievement_pct, 0) < 100
    ) order by coalesce(mr.actual_nominal, 0) desc, coalesce(mr.nickname, mr.full_name))
    from monthly_rows mr
  ), '[]'::json)
);
$function$;

grant execute on function public.get_sator_home_promotor_cards(uuid) to authenticated;
