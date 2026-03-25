create or replace function public.get_sator_aktivitas_tim(
  p_sator_id uuid,
  p_date date default current_date
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
begin
  return (
    with promotor_ids as (
      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = p_sator_id
        and hsp.active = true
    ),
    sator_store_scope as (
      select ass.store_id
      from public.assignments_sator_store ass
      where ass.sator_id = p_sator_id
        and ass.active = true
    ),
    promotor_assignments as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        aps.store_id,
        aps.created_at
      from public.assignments_promotor_store aps
      join promotor_ids pi on pi.promotor_id = aps.promotor_id
      where aps.active = true
        and (
          not exists (select 1 from sator_store_scope)
          or aps.store_id in (select sss.store_id from sator_store_scope sss)
        )
      order by aps.promotor_id, aps.created_at desc, aps.store_id
    ),
    store_data as (
      select distinct
        st.id as store_id,
        st.store_name
      from public.stores st
      join promotor_assignments pa on pa.store_id = st.id
    ),
    promotor_checklist as (
      select
        u.id as promotor_id,
        u.full_name as name,
        pa.store_id,
        exists(
          select 1
          from public.attendance a
          where a.user_id = u.id
            and a.attendance_date = p_date
            and a.clock_in is not null
        ) as clock_in,
        exists(
          select 1
          from public.sales_sell_out sso
          where sso.promotor_id = u.id
            and sso.transaction_date = p_date
            and sso.deleted_at is null
        ) as sell_out,
        exists(
          select 1
          from public.stock_movement_log sml
          where sml.moved_by = u.id
            and sml.movement_type in ('initial', 'transfer_in', 'adjustment')
            and (sml.moved_at at time zone 'Asia/Makassar')::date = p_date
        ) as stock_input,
        exists(
          select 1
          from public.stock_validations sv
          where sv.promotor_id = u.id
            and sv.validation_date = p_date
        ) as stock_validation,
        exists(
          select 1
          from public.promotion_reports pr
          where pr.promotor_id = u.id
            and (pr.created_at at time zone 'Asia/Makassar')::date = p_date
        ) as promotion,
        exists(
          select 1
          from public.follower_reports fr
          where fr.promotor_id = u.id
            and (fr.created_at at time zone 'Asia/Makassar')::date = p_date
        ) as follower,
        exists(
          select 1
          from public.allbrand_reports abr
          where abr.promotor_id = u.id
            and abr.report_date = p_date
        ) as allbrand
      from public.users u
      join promotor_ids pi on pi.promotor_id = u.id
      join promotor_assignments pa on pa.promotor_id = u.id
    )
    select coalesce(
      json_agg(
        json_build_object(
          'store_id', sd.store_id,
          'store_name', sd.store_name,
          'promotors', (
            select coalesce(
              json_agg(
                json_build_object(
                  'id', pc.promotor_id,
                  'name', pc.name,
                  'clock_in', pc.clock_in,
                  'sell_out', pc.sell_out,
                  'stock_input', pc.stock_input,
                  'stock_validation', pc.stock_validation,
                  'promotion', pc.promotion,
                  'follower', pc.follower,
                  'allbrand', pc.allbrand
                )
                order by pc.name
              ),
              '[]'::json
            )
            from promotor_checklist pc
            where pc.store_id = sd.store_id
          )
        )
        order by sd.store_name
      ),
      '[]'::json
    )
    from store_data sd
  );
end;
$$;

grant execute on function public.get_sator_aktivitas_tim(uuid, date) to authenticated;

create or replace function public.get_store_promotor_checklist(
  p_store_id uuid,
  p_date date default current_date
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
begin
  return (
    with active_promotors as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        u.full_name,
        u.promotor_type,
        aps.created_at
      from public.assignments_promotor_store aps
      join public.users u
        on u.id = aps.promotor_id
      where aps.store_id = p_store_id
        and aps.active = true
        and u.status = 'active'
      order by aps.promotor_id, aps.created_at desc nulls last
    )
    select coalesce(
      json_agg(
        json_build_object(
          'id', ap.promotor_id,
          'name', ap.full_name,
          'promotor_type', ap.promotor_type,
          'clock_in', exists(
            select 1
            from public.attendance a
            where a.user_id = ap.promotor_id
              and a.attendance_date = p_date
              and a.clock_in is not null
          ),
          'sell_out', exists(
            select 1
            from public.sales_sell_out sso
            where sso.promotor_id = ap.promotor_id
              and sso.store_id = p_store_id
              and sso.transaction_date = p_date
              and sso.deleted_at is null
          ),
          'stock_input', exists(
            select 1
            from public.stock_movement_log sml
            where sml.moved_by = ap.promotor_id
              and coalesce(sml.to_store_id, sml.from_store_id) = p_store_id
              and sml.movement_type in ('initial', 'transfer_in', 'adjustment')
              and (sml.moved_at at time zone 'Asia/Makassar')::date = p_date
          ),
          'stock_validation', exists(
            select 1
            from public.stock_validations sv
            where sv.promotor_id = ap.promotor_id
              and sv.store_id = p_store_id
              and (sv.created_at at time zone 'Asia/Makassar')::date = p_date
          ),
          'promotion', exists(
            select 1
            from public.promotion_reports pr
            where pr.promotor_id = ap.promotor_id
              and pr.store_id = p_store_id
              and (pr.created_at at time zone 'Asia/Makassar')::date = p_date
          ),
          'follower', exists(
            select 1
            from public.follower_reports fr
            where fr.promotor_id = ap.promotor_id
              and fr.store_id = p_store_id
              and (fr.created_at at time zone 'Asia/Makassar')::date = p_date
          ),
          'allbrand', exists(
            select 1
            from public.allbrand_reports abr
            where abr.promotor_id = ap.promotor_id
              and abr.store_id = p_store_id
              and abr.report_date = p_date
          )
        )
        order by ap.full_name
      ),
      '[]'::json
    )
    from active_promotors ap
  );
end;
$$;

grant execute on function public.get_store_promotor_checklist(uuid, date) to authenticated;
