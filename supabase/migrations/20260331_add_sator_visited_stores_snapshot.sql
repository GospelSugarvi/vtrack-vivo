create or replace function public.get_sator_visited_stores(
  p_sator_id uuid,
  p_month date default current_date,
  p_date date default null
)
returns json
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_month_start date := date_trunc('month', coalesce(p_month, current_date))::date;
  v_month_end date := (date_trunc('month', coalesce(p_month, current_date)) + interval '1 month - 1 day')::date;
begin
  return (
    with promotor_ids as (
      select promotor_id
      from public.hierarchy_sator_promotor
      where sator_id = p_sator_id
        and active = true
    ),
    direct_store_ids as (
      select distinct ass.store_id
      from public.assignments_sator_store ass
      where ass.sator_id = p_sator_id
        and ass.active = true
    ),
    promotor_store_ids as (
      select distinct aps.store_id
      from public.assignments_promotor_store aps
      where aps.promotor_id in (select promotor_id from promotor_ids)
        and aps.active = true
    ),
    store_ids as (
      select store_id from direct_store_ids
      union
      select store_id from promotor_store_ids
    ),
    monthly_visits as (
      select
        sv.store_id,
        count(*)::int as month_visit_count,
        max(coalesce(sv.check_in_time, sv.created_at)) as last_visit_at
      from public.store_visits sv
      where sv.sator_id = p_sator_id
        and sv.store_id in (select store_id from store_ids)
        and sv.visit_date between v_month_start and v_month_end
      group by sv.store_id
    ),
    daily_visits as (
      select
        sv.store_id,
        count(*)::int as day_visit_count
      from public.store_visits sv
      where sv.sator_id = p_sator_id
        and sv.store_id in (select store_id from store_ids)
        and p_date is not null
        and sv.visit_date = p_date
      group by sv.store_id
    ),
    filtered_visit_rows as (
      select
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
      where sv.sator_id = p_sator_id
        and sv.store_id in (select store_id from store_ids)
        and (
          (p_date is not null and sv.visit_date = p_date)
          or (
            p_date is null
            and sv.visit_date between v_month_start and v_month_end
          )
        )
      group by sv.store_id
    ),
    scoped as (
      select
        st.id as store_id,
        coalesce(st.store_name, 'Toko') as store_name,
        coalesce(st.address, '') as address,
        coalesce(st.area, '') as area,
        coalesce(mv.month_visit_count, 0) as month_visit_count,
        coalesce(dv.day_visit_count, 0) as day_visit_count,
        mv.last_visit_at,
        coalesce(fvr.rows, '[]'::json) as visit_rows
      from public.stores st
      join store_ids si on si.store_id = st.id
      left join monthly_visits mv on mv.store_id = st.id
      left join daily_visits dv on dv.store_id = st.id
      left join filtered_visit_rows fvr on fvr.store_id = st.id
    )
    select coalesce(
      json_agg(
        json_build_object(
          'store_id', s.store_id,
          'store_name', s.store_name,
          'address', s.address,
          'area', s.area,
          'month_visit_count', s.month_visit_count,
          'day_visit_count', s.day_visit_count,
          'last_visit_at', s.last_visit_at,
          'visit_rows', s.visit_rows
        )
        order by
          case when p_date is not null then coalesce(s.day_visit_count, 0) else coalesce(s.month_visit_count, 0) end desc,
          s.last_visit_at desc nulls last,
          s.store_name
      ),
      '[]'::json
    )
    from scoped s
    where s.month_visit_count > 0
      and (p_date is null or s.day_visit_count > 0)
  );
end;
$function$;

grant execute on function public.get_sator_visited_stores(uuid, date, date) to authenticated;
