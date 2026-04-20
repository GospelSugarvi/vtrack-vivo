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
        scope_sator.sator_id,
        scope_sator.sator_name,
        st.id as store_id,
        coalesce(st.store_name, '-') as store_name,
        coalesce(st.area, '') as area
      from sator_scope scope_sator
      join public.assignments_sator_store ass
        on ass.sator_id = scope_sator.sator_id
       and ass.active = true
      join public.stores st
        on st.id = ass.store_id
    ),
    report_ranked as (
      select
        scope_store.area,
        scope_store.sator_name,
        ar.store_id,
        scope_store.store_name,
        ar.report_date,
        ar.created_at,
        ar.updated_at,
        coalesce(ar.brand_data, '{}'::jsonb) as brand_data,
        coalesce(ar.leasing_sales, '{}'::jsonb) as leasing_sales,
        coalesce(ar.vivo_auto_data, '{}'::jsonb) as vivo_auto_data,
        coalesce(ar.vivo_promotor_count, 0)::int as vivo_promotor_count,
        row_number() over (
          partition by ar.store_id
          order by ar.report_date desc, ar.updated_at desc nulls last, ar.created_at desc nulls last
        ) as rn
      from public.allbrand_reports ar
      join store_scope scope_store
        on scope_store.store_id = ar.store_id
      where ar.report_date between p_start_date and p_end_date
    ),
    latest_report as (
      select *
      from report_ranked
      where rn = 1
    ),
    rows_payload as (
      select
        lr.area,
        lr.sator_name,
        lr.store_name,
        lr.report_date,
        lr.brand_data,
        lr.leasing_sales,
        lr.vivo_auto_data,
        lr.vivo_promotor_count,
        coalesce(
          nullif(lr.vivo_auto_data ->> 'total', '')::int,
          coalesce(nullif(lr.vivo_auto_data ->> 'under_2m', '')::int, 0) +
          coalesce(nullif(lr.vivo_auto_data ->> '2m_4m', '')::int, 0) +
          coalesce(nullif(lr.vivo_auto_data ->> '4m_6m', '')::int, 0) +
          coalesce(nullif(lr.vivo_auto_data ->> 'above_6m', '')::int, 0)
        )::int as total_vivo_unit,
        (
          coalesce(
            nullif(lr.vivo_auto_data ->> 'total', '')::int,
            coalesce(nullif(lr.vivo_auto_data ->> 'under_2m', '')::int, 0) +
            coalesce(nullif(lr.vivo_auto_data ->> '2m_4m', '')::int, 0) +
            coalesce(nullif(lr.vivo_auto_data ->> '4m_6m', '')::int, 0) +
            coalesce(nullif(lr.vivo_auto_data ->> 'above_6m', '')::int, 0)
          ) + public.sum_allbrand_brand_units(lr.brand_data)
        )::int as total_unit_allbrand_toko
      from latest_report lr
    )
    select jsonb_build_object(
      'rows',
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'area', rp.area,
            'sator_name', rp.sator_name,
            'store_name', rp.store_name,
            'report_date', rp.report_date,
            'total_unit_allbrand_toko', rp.total_unit_allbrand_toko,
            'total_vivo_unit', rp.total_vivo_unit,
            'brand_data', rp.brand_data,
            'leasing_sales', rp.leasing_sales,
            'vivo_auto_data', rp.vivo_auto_data,
            'vivo_promotor_count', rp.vivo_promotor_count
          )
          order by rp.area, rp.sator_name, rp.store_name
        )
        from rows_payload rp
      ), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_export_allbrand_snapshot(date, date) to authenticated;
