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
    monthly_visits as (
      select
        sv.sator_id,
        sv.store_id,
        count(*)::int as visit_count,
        max(coalesce(sv.check_in_time, sv.created_at)) as last_visit_at
      from public.store_visits sv
      where sv.sator_id in (select sator_id from sator_scope)
        and sv.visit_date between v_month_start and v_month_end
      group by sv.sator_id, sv.store_id
    ),
    daily_visits as (
      select
        sv.sator_id,
        sv.store_id,
        count(*)::int as day_visit_count
      from public.store_visits sv
      where sv.sator_id in (select sator_id from sator_scope)
        and sv.visit_date = v_target_date
      group by sv.sator_id, sv.store_id
    ),
    monthly_visit_rows as (
      select
        sv.sator_id,
        sv.store_id,
        json_agg(
          json_build_object(
            'visit_id', sv.id,
            'visit_date', sv.visit_date,
            'visit_time', coalesce(sv.check_in_time, sv.created_at),
            'notes', coalesce(sv.notes, ''),
            'photos', array_remove(array[sv.check_in_photo, sv.check_out_photo], null)
          )
          order by coalesce(sv.check_in_time, sv.created_at) desc
        ) as rows
      from public.store_visits sv
      where sv.sator_id in (select sator_id from sator_scope)
        and sv.visit_date between v_month_start and v_month_end
      group by sv.sator_id, sv.store_id
    ),
    daily_visit_rows as (
      select
        sv.sator_id,
        sv.store_id,
        json_agg(
          json_build_object(
            'visit_id', sv.id,
            'visit_date', sv.visit_date,
            'visit_time', coalesce(sv.check_in_time, sv.created_at),
            'notes', coalesce(sv.notes, ''),
            'photos', array_remove(array[sv.check_in_photo, sv.check_out_photo], null)
          )
          order by coalesce(sv.check_in_time, sv.created_at) desc
        ) as rows
      from public.store_visits sv
      where sv.sator_id in (select sator_id from sator_scope)
        and sv.visit_date = v_target_date
      group by sv.sator_id, sv.store_id
    ),
    latest_visits as (
      select
        sv.sator_id,
        sv.store_id,
        max(coalesce(sv.check_in_time, sv.created_at)) as last_visit_at
      from public.store_visits sv
      where sv.sator_id in (select sator_id from sator_scope)
      group by sv.sator_id, sv.store_id
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
        coalesce(mv.last_visit_at, lv.last_visit_at) as last_visit_at,
        coalesce(dvr.rows, mvr.rows, '[]'::json) as visit_rows
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
    ),
    rows as (
      select coalesce(
        jsonb_agg(
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
        ),
        '[]'::jsonb
      ) as data
      from per_sator ps
    ),
    summary as (
      select jsonb_build_object(
        'sator_count', count(*)::int,
        'total_stores', coalesce(sum(ps.total_stores), 0)::int,
        'visited_stores', coalesce(sum(ps.visited_stores), 0)::int,
        'total_visits', coalesce(sum(ps.total_visits), 0)::int
      ) as data
      from per_sator ps
    )
    select jsonb_build_object(
      'month_start', v_month_start,
      'month_end', v_month_end,
      'target_date', v_target_date,
      'summary', coalesce((select data from summary), '{}'::jsonb),
      'rows', coalesce((select data from rows), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_spv_visiting_monitor_snapshot(date) to authenticated;
