create or replace function public.get_sator_allbrand_daily_monitor(
  p_sator_id uuid,
  p_date date
)
returns table (
  store_id uuid,
  store_name text,
  promotor_count integer,
  report_id uuid,
  report_date date,
  submitted_by_id uuid,
  submitted_by_name text,
  submitted_at timestamptz,
  daily_total_units integer,
  cumulative_total_units integer,
  status text
)
language sql
security definer
set search_path = public
as $$
  with assigned_stores as (
    select distinct on (ass.store_id)
      ass.store_id,
      s.store_name
    from public.assignments_sator_store ass
    join public.stores s
      on s.id = ass.store_id
    where ass.sator_id = p_sator_id
      and ass.active = true
    order by ass.store_id, ass.created_at desc, ass.id desc
  ),
  promotor_counts as (
    select
      aps.store_id,
      count(distinct aps.promotor_id)::int as promotor_count
    from public.assignments_promotor_store aps
    join assigned_stores ast
      on ast.store_id = aps.store_id
    where aps.active = true
    group by aps.store_id
  )
  select
    ast.store_id,
    ast.store_name,
    coalesce(pc.promotor_count, 0) as promotor_count,
    rpt.id as report_id,
    rpt.report_date,
    rpt.promotor_id as submitted_by_id,
    u.full_name as submitted_by_name,
    coalesce(rpt.updated_at, rpt.created_at) as submitted_at,
    coalesce(rpt.daily_total_units, 0) as daily_total_units,
    coalesce(rpt.cumulative_total_units, 0) as cumulative_total_units,
    case
      when rpt.id is null then 'belum_kirim'
      else 'sudah_kirim'
    end as status
  from assigned_stores ast
  left join promotor_counts pc
    on pc.store_id = ast.store_id
  left join lateral (
    select
      ar.id,
      ar.report_date,
      ar.promotor_id,
      ar.created_at,
      ar.updated_at,
      ar.daily_total_units,
      ar.cumulative_total_units
    from public.allbrand_reports ar
    where ar.store_id = ast.store_id
      and ar.report_date = p_date
    order by ar.updated_at desc nulls last, ar.created_at desc nulls last, ar.id desc
    limit 1
  ) rpt on true
  left join public.users u
    on u.id = rpt.promotor_id
  order by
    case when rpt.id is null then 1 else 0 end,
    ast.store_name;
$$;

create or replace function public.get_spv_allbrand_daily_monitor(
  p_spv_id uuid,
  p_date date
)
returns table (
  sator_id uuid,
  sator_name text,
  store_id uuid,
  store_name text,
  promotor_count integer,
  report_id uuid,
  report_date date,
  submitted_by_id uuid,
  submitted_by_name text,
  submitted_at timestamptz,
  daily_total_units integer,
  cumulative_total_units integer,
  status text
)
language sql
security definer
set search_path = public
as $$
  with linked_sators as (
    select
      hss.sator_id,
      su.full_name as sator_name
    from public.hierarchy_spv_sator hss
    join public.users su
      on su.id = hss.sator_id
    where hss.spv_id = p_spv_id
      and hss.active = true
  ),
  assigned_stores as (
    select distinct on (ass.store_id)
      ls.sator_id,
      ls.sator_name,
      ass.store_id,
      s.store_name
    from linked_sators ls
    join public.assignments_sator_store ass
      on ass.sator_id = ls.sator_id
     and ass.active = true
    join public.stores s
      on s.id = ass.store_id
    order by ass.store_id, ass.created_at desc, ass.id desc, ls.sator_name
  ),
  promotor_counts as (
    select
      aps.store_id,
      count(distinct aps.promotor_id)::int as promotor_count
    from public.assignments_promotor_store aps
    join assigned_stores ast
      on ast.store_id = aps.store_id
    where aps.active = true
    group by aps.store_id
  )
  select
    ast.sator_id,
    ast.sator_name,
    ast.store_id,
    ast.store_name,
    coalesce(pc.promotor_count, 0) as promotor_count,
    rpt.id as report_id,
    rpt.report_date,
    rpt.promotor_id as submitted_by_id,
    u.full_name as submitted_by_name,
    coalesce(rpt.updated_at, rpt.created_at) as submitted_at,
    coalesce(rpt.daily_total_units, 0) as daily_total_units,
    coalesce(rpt.cumulative_total_units, 0) as cumulative_total_units,
    case
      when rpt.id is null then 'belum_kirim'
      else 'sudah_kirim'
    end as status
  from assigned_stores ast
  left join promotor_counts pc
    on pc.store_id = ast.store_id
  left join lateral (
    select
      ar.id,
      ar.report_date,
      ar.promotor_id,
      ar.created_at,
      ar.updated_at,
      ar.daily_total_units,
      ar.cumulative_total_units
    from public.allbrand_reports ar
    where ar.store_id = ast.store_id
      and ar.report_date = p_date
    order by ar.updated_at desc nulls last, ar.created_at desc nulls last, ar.id desc
    limit 1
  ) rpt on true
  left join public.users u
    on u.id = rpt.promotor_id
  order by
    case when rpt.id is null then 1 else 0 end,
    ast.sator_name,
    ast.store_name;
$$;

grant execute on function public.get_sator_allbrand_daily_monitor(uuid, date) to authenticated;
grant execute on function public.get_spv_allbrand_daily_monitor(uuid, date) to authenticated;
