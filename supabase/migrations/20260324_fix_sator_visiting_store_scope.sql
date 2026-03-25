create or replace function public.get_sator_visiting_stores(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $function$
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
    )
    select coalesce(
      json_agg(
        json_build_object(
          'store_id', st.id,
          'store_name', st.store_name,
          'address', st.address,
          'area', st.area,
          'last_visit', (
            select max(sv.created_at)
            from public.store_visits sv
            where sv.store_id = st.id
              and sv.sator_id = p_sator_id
          ),
          'issue_count', (
            select count(*)
            from public.store_issues si
            where si.store_id = st.id
              and si.resolved = false
          ),
          'priority', case
            when (
              select count(*)
              from public.store_issues si
              where si.store_id = st.id
                and si.resolved = false
            ) > 0 then 1
            when (
              select max(sv.created_at)
              from public.store_visits sv
              where sv.store_id = st.id
                and sv.sator_id = p_sator_id
            ) is null then 2
            when (
              select max(sv.created_at)
              from public.store_visits sv
              where sv.store_id = st.id
                and sv.sator_id = p_sator_id
            ) < now() - interval '7 days' then 3
            else 4
          end
        )
        order by
          case
            when (
              select count(*)
              from public.store_issues si
              where si.store_id = st.id
                and si.resolved = false
            ) > 0 then 1
            when (
              select max(sv.created_at)
              from public.store_visits sv
              where sv.store_id = st.id
                and sv.sator_id = p_sator_id
            ) is null then 2
            when (
              select max(sv.created_at)
              from public.store_visits sv
              where sv.store_id = st.id
                and sv.sator_id = p_sator_id
            ) < now() - interval '7 days' then 3
            else 4
          end,
          st.store_name
      ),
      '[]'::json
    )
    from public.stores st
    where st.id in (select store_id from store_ids)
  );
end;
$function$;

grant execute on function public.get_sator_visiting_stores(uuid) to authenticated;
