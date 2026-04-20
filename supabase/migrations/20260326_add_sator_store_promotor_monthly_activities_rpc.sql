create or replace function public.get_sator_store_promotor_monthly_activities(
  p_sator_id uuid,
  p_store_id uuid,
  p_date date default current_date
)
returns json
language sql
security definer
set search_path = public
as $$
  with scope_guard as (
    select 1
    from public.assignments_sator_store ass
    where ass.sator_id = p_sator_id
      and ass.store_id = p_store_id
      and ass.active = true
    limit 1
  ),
  bounds as (
    select
      date_trunc('month', p_date)::date as month_start,
      (date_trunc('month', p_date) + interval '1 month')::date as next_month
  ),
  active_promotors as (
    select distinct on (aps.promotor_id)
      aps.promotor_id,
      coalesce(u.nickname, u.full_name) as promotor_name
    from public.assignments_promotor_store aps
    join public.users u on u.id = aps.promotor_id
    where aps.store_id = p_store_id
      and aps.active = true
      and u.status = 'active'
      and exists (select 1 from scope_guard)
    order by aps.promotor_id, aps.created_at desc nulls last
  ),
  rows as (
    select
      ap.promotor_id,
      ap.promotor_name,
      (
        select count(distinct a.attendance_date)::int
        from public.attendance a
        cross join bounds b
        where a.user_id = ap.promotor_id
          and a.clock_in is not null
          and a.attendance_date >= b.month_start
          and a.attendance_date < b.next_month
      ) as month_attendance_days,
      (
        select count(*)::int
        from public.sales_sell_out s
        cross join bounds b
        where s.promotor_id = ap.promotor_id
          and s.store_id = p_store_id
          and s.deleted_at is null
          and s.transaction_date >= b.month_start
          and s.transaction_date < b.next_month
      ) as month_sellout_count,
      (
        select count(*)::int
        from public.stock_movement_log sml
        cross join bounds b
        where sml.moved_by = ap.promotor_id
          and coalesce(sml.to_store_id, sml.from_store_id) = p_store_id
          and (sml.moved_at at time zone 'Asia/Makassar')::date >= b.month_start
          and (sml.moved_at at time zone 'Asia/Makassar')::date < b.next_month
      ) as month_stock_input_count,
      (
        select count(*)::int
        from public.promotion_reports pr
        cross join bounds b
        where pr.promotor_id = ap.promotor_id
          and pr.store_id = p_store_id
          and (coalesce(pr.posted_at, pr.created_at) at time zone 'Asia/Makassar')::date >= b.month_start
          and (coalesce(pr.posted_at, pr.created_at) at time zone 'Asia/Makassar')::date < b.next_month
      ) as month_promotion_count,
      (
        select count(*)::int
        from public.follower_reports fr
        cross join bounds b
        where fr.promotor_id = ap.promotor_id
          and fr.store_id = p_store_id
          and (coalesce(fr.followed_at, fr.created_at) at time zone 'Asia/Makassar')::date >= b.month_start
          and (coalesce(fr.followed_at, fr.created_at) at time zone 'Asia/Makassar')::date < b.next_month
      ) as month_follower_count,
      (
        select count(*)::int
        from public.allbrand_reports ar
        cross join bounds b
        where ar.promotor_id = ap.promotor_id
          and ar.store_id = p_store_id
          and ar.report_date >= b.month_start
          and ar.report_date < b.next_month
      ) as month_allbrand_count
    from active_promotors ap
  )
  select coalesce(
    json_agg(
      json_build_object(
        'promotor_id', r.promotor_id,
        'promotor_name', r.promotor_name,
        'month_attendance_days', coalesce(r.month_attendance_days, 0),
        'month_sellout_count', coalesce(r.month_sellout_count, 0),
        'month_stock_input_count', coalesce(r.month_stock_input_count, 0),
        'month_promotion_count', coalesce(r.month_promotion_count, 0),
        'month_follower_count', coalesce(r.month_follower_count, 0),
        'month_allbrand_count', coalesce(r.month_allbrand_count, 0)
      )
      order by r.promotor_name
    ),
    '[]'::json
  )
  from rows r;
$$;

grant execute on function public.get_sator_store_promotor_monthly_activities(uuid, uuid, date) to authenticated;
