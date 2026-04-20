set check_function_bodies = off;

-- Backfill toko promotor ke assignment SATOR agar cakupan toko hanya bertumpu pada assignments_sator_store.
insert into public.assignments_sator_store (
  sator_id,
  store_id,
  active
)
select distinct
  hsp.sator_id,
  aps.store_id,
  true
from public.assignments_promotor_store aps
join public.hierarchy_sator_promotor hsp
  on hsp.promotor_id = aps.promotor_id
 and hsp.active = true
left join public.assignments_sator_store ass
  on ass.sator_id = hsp.sator_id
 and ass.store_id = aps.store_id
where aps.active = true
  and ass.id is null;

create or replace function public.get_store_stock_status(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result json;
begin
  select coalesce(
    json_agg(
      json_build_object(
        'store_id', st.id,
        'store_name', st.store_name,
        'area', st.area,
        'group_id', st.group_id,
        'group_name', sg.group_name,
        'empty_count', (
          select count(*)
          from public.store_inventory si
          where si.store_id = st.id
            and si.quantity = 0
        ),
        'low_count', (
          select count(*)
          from public.store_inventory si
          where si.store_id = st.id
            and si.quantity > 0
            and si.quantity < 3
        )
      )
      order by coalesce(sg.group_name, ''), st.store_name
    ),
    '[]'::json
  )
  into v_result
  from public.assignments_sator_store ass
  join public.stores st
    on st.id = ass.store_id
  left join public.store_groups sg
    on sg.id = st.group_id
  where ass.sator_id = p_sator_id
    and ass.active = true;

  return v_result;
end;
$$;

grant execute on function public.get_store_stock_status(uuid) to authenticated;

create or replace function public.get_spv_visiting_monitor_snapshot(
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_target_date date := coalesce(p_date, current_date);
  v_month_start date := date_trunc('month', v_target_date)::date;
  v_month_end date := (date_trunc('month', v_target_date) + interval '1 month - 1 day')::date;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'spv' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return (
    with sator_scope as (
      select
        hss.sator_id,
        coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'SATOR')) as name
      from public.hierarchy_spv_sator hss
      join public.users u on u.id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
    ),
    assigned as (
      select distinct
        ass.sator_id,
        st.id as store_id,
        coalesce(st.store_name, 'Toko') as store_name,
        coalesce(st.address, '') as address,
        coalesce(st.area, '') as area
      from public.assignments_sator_store ass
      join public.stores st on st.id = ass.store_id
      where ass.sator_id in (select sator_id from sator_scope)
        and ass.active = true
    ),
    visit_scope as (
      select
        sv.store_id,
        sv.visit_date,
        coalesce(sv.check_in_time, sv.created_at) as visit_time,
        coalesce(sv.notes, '') as notes,
        array_remove(array[sv.check_in_photo, sv.check_out_photo], null) as photos,
        coalesce(sv.sator_id, null) as sator_id
      from public.store_visits sv
      where sv.sator_id in (select sator_id from sator_scope)
    ),
    monthly_visits as (
      select
        vs.sator_id,
        vs.store_id,
        count(*)::int as visit_count,
        max(vs.visit_time) as last_visit_at
      from visit_scope vs
      where vs.visit_date between v_month_start and v_month_end
      group by vs.sator_id, vs.store_id
    ),
    daily_visits as (
      select
        vs.sator_id,
        vs.store_id,
        count(*)::int as day_visit_count
      from visit_scope vs
      where vs.visit_date = v_target_date
      group by vs.sator_id, vs.store_id
    ),
    monthly_visit_rows as (
      select
        vs.sator_id,
        vs.store_id,
        json_agg(
          json_build_object(
            'visit_date', vs.visit_date,
            'visit_time', vs.visit_time,
            'notes', vs.notes,
            'photos', vs.photos
          )
          order by vs.visit_time desc
        ) as rows
      from visit_scope vs
      where vs.visit_date between v_month_start and v_month_end
      group by vs.sator_id, vs.store_id
    ),
    daily_visit_rows as (
      select
        vs.sator_id,
        vs.store_id,
        json_agg(
          json_build_object(
            'visit_date', vs.visit_date,
            'visit_time', vs.visit_time,
            'notes', vs.notes,
            'photos', vs.photos
          )
          order by vs.visit_time desc
        ) as rows
      from visit_scope vs
      where vs.visit_date = v_target_date
      group by vs.sator_id, vs.store_id
    ),
    latest_visits as (
      select
        vs.sator_id,
        vs.store_id,
        max(vs.visit_time) as last_visit_at
      from visit_scope vs
      group by vs.sator_id, vs.store_id
    ),
    per_store as (
      select
        a.sator_id,
        a.store_id,
        a.store_name,
        a.address,
        a.area,
        coalesce(mv.visit_count, 0) as visit_count,
        coalesce(dv.day_visit_count, 0) as day_visit_count,
        coalesce(dvr.rows, mvr.rows, '[]'::json) as visit_rows,
        coalesce(mv.last_visit_at, lv.last_visit_at) as last_visit_at
      from assigned a
      left join monthly_visits mv
        on mv.sator_id = a.sator_id
       and mv.store_id = a.store_id
      left join daily_visits dv
        on dv.sator_id = a.sator_id
       and dv.store_id = a.store_id
      left join daily_visit_rows dvr
        on dvr.sator_id = a.sator_id
       and dvr.store_id = a.store_id
      left join monthly_visit_rows mvr
        on mvr.sator_id = a.sator_id
       and mvr.store_id = a.store_id
      left join latest_visits lv
        on lv.sator_id = a.sator_id
       and lv.store_id = a.store_id
    ),
    per_sator as (
      select
        ss.sator_id,
        ss.name,
        count(ps.store_id)::int as total_stores,
        count(*) filter (where ps.visit_count > 0)::int as visited_stores,
        coalesce(sum(ps.visit_count), 0)::int as total_visits,
        case
          when count(ps.store_id) > 0
            then round((count(*) filter (where ps.visit_count > 0)::numeric * 100) / count(ps.store_id)::numeric, 1)
          else 0
        end as pct,
        coalesce(
          jsonb_agg(
            jsonb_build_object(
              'store_id', ps.store_id,
              'store_name', ps.store_name,
              'address', ps.address,
              'area', ps.area,
              'visit_count', ps.visit_count,
              'day_visit_count', ps.day_visit_count,
              'last_visit_at', ps.last_visit_at,
              'visit_rows', ps.visit_rows,
              'status', case
                when ps.day_visit_count > 0 then 'Sudah divisit di tanggal ini'
                when ps.visit_count > 0 then 'Sudah divisit bulan ini'
                when ps.last_visit_at is null then 'Belum pernah divisit'
                else 'Belum divisit bulan ini'
              end
            )
            order by ps.day_visit_count desc, ps.visit_count desc, ps.store_name
          ) filter (where ps.store_id is not null),
          '[]'::jsonb
        ) as stores
      from sator_scope ss
      left join per_store ps on ps.sator_id = ss.sator_id
      group by ss.sator_id, ss.name
    )
    select jsonb_build_object(
      'month_start', v_month_start,
      'month_end', v_month_end,
      'target_date', v_target_date,
      'summary', (
        select jsonb_build_object(
          'sator_count', count(*)::int,
          'total_stores', coalesce(sum(ps.total_stores), 0)::int,
          'visited_stores', coalesce(sum(ps.visited_stores), 0)::int,
          'total_visits', coalesce(sum(ps.total_visits), 0)::int
        )
        from per_sator ps
      ),
      'rows', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'sator_id', ps.sator_id,
            'name', ps.name,
            'total_stores', ps.total_stores,
            'visited_stores', ps.visited_stores,
            'total_visits', ps.total_visits,
            'pct', ps.pct,
            'stores', ps.stores
          )
          order by ps.visited_stores desc, ps.total_visits desc, ps.name
        )
        from per_sator ps
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_spv_visiting_monitor_snapshot(date) to authenticated;

create or replace function public.get_export_allbrand_snapshot(
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select u.role
  into v_actor_role
  from public.users u
  where u.id = v_actor_id;

  if v_actor_role not in ('sator', 'spv') then
    raise exception 'Role ini belum didukung untuk export AllBrand.';
  end if;

  return (
    with sator_scope as (
      select
        v_actor_id as sator_id,
        coalesce(u.full_name, 'SATOR') as sator_name
      from public.users u
      where v_actor_role = 'sator'
        and u.id = v_actor_id
      union all
      select
        su.id as sator_id,
        coalesce(su.full_name, 'SATOR') as sator_name
      from public.hierarchy_spv_sator hss
      join public.users su on su.id = hss.sator_id
      where v_actor_role = 'spv'
        and hss.spv_id = v_actor_id
        and hss.active = true
    ),
    store_scope as (
      select distinct
        ss.sator_id,
        ss.sator_name,
        st.id as store_id,
        coalesce(st.store_name, '-') as store_name,
        coalesce(st.area, '') as area
      from sator_scope ss
      join public.assignments_sator_store ass
        on ass.sator_id = ss.sator_id
       and ass.active = true
      join public.stores st
        on st.id = ass.store_id
    ),
    report_ranked as (
      select
        ss.area,
        ss.sator_name,
        ar.store_id,
        ss.store_name,
        ar.report_date,
        ar.created_at,
        ar.updated_at,
        coalesce(ar.brand_data, '{}'::jsonb) as brand_data,
        coalesce(ar.vivo_auto_data, '{}'::jsonb) as vivo_auto_data,
        row_number() over (
          partition by ar.store_id
          order by ar.report_date desc, ar.updated_at desc nulls last, ar.created_at desc nulls last
        ) as rn
      from public.allbrand_reports ar
      join store_scope ss
        on ss.store_id = ar.store_id
      where ar.report_date between p_start_date and p_end_date
    ),
    latest_report as (
      select *
      from report_ranked
      where rn = 1
    ),
    sales_cumulative as (
      select
        lr.store_id,
        count(*)::int as vivo_units_total
      from latest_report lr
      left join public.sales_sell_out sso
        on sso.store_id = lr.store_id
       and sso.transaction_date <= lr.report_date
       and sso.deleted_at is null
      group by lr.store_id
    ),
    ranges as (
      select * from (
        values
          ('under_2m', '< 2 Jt', 1),
          ('2m_4m', '2 - 4 Jt', 2),
          ('4m_6m', '4 - 6 Jt', 3),
          ('above_6m', '> 6 Jt', 4)
      ) as x(range_key, range_label, sort_order)
    ),
    rows_payload as (
      select
        lr.area,
        lr.sator_name,
        lr.store_name,
        coalesce(sc.vivo_units_total, 0) as total_vivo_unit,
        (
          coalesce(sc.vivo_units_total, 0)
          + public.sum_allbrand_brand_units(lr.brand_data)
        )::int as total_unit_allbrand_toko,
        r.range_key,
        r.range_label,
        coalesce(nullif(lr.vivo_auto_data ->> r.range_key, '')::int, 0) as vivo_range_unit,
        (
          select coalesce(
            string_agg(format('%s %s', brand_key, qty), ' | ' order by brand_key),
            '-'
          )
          from (
            select
              brand.key as brand_key,
              coalesce(nullif(brand.value ->> r.range_key, '')::int, 0) as qty
            from jsonb_each(lr.brand_data) brand
          ) q
          where q.qty > 0
        ) as brand_lain
      from latest_report lr
      left join sales_cumulative sc
        on sc.store_id = lr.store_id
      cross join ranges r
    )
    select jsonb_build_object(
      'rows',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'area', rp.area,
            'sator_name', rp.sator_name,
            'store_name', rp.store_name,
            'total_unit_allbrand_toko', rp.total_unit_allbrand_toko,
            'total_vivo_unit', rp.total_vivo_unit,
            'range_key', rp.range_key,
            'range_label', rp.range_label,
            'vivo_range_unit', rp.vivo_range_unit,
            'brand_lain', rp.brand_lain
          )
          order by rp.area, rp.sator_name, rp.store_name, rp.range_key
        )
        from rows_payload rp
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_export_allbrand_snapshot(date, date) to authenticated;
