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
    ),
    active_promotors as (
      select
        aps.store_id,
        aps.promotor_id
      from public.assignments_promotor_store aps
      join public.users u on u.id = aps.promotor_id
      where aps.active = true
        and aps.store_id in (select store_id from store_ids)
        and u.status = 'active'
      group by aps.store_id, aps.promotor_id
    ),
    target_summary as (
      select
        ap.store_id,
        coalesce(sum(ut.target_omzet), 0)::int as monthly_target_omzet
      from active_promotors ap
      left join public.user_targets ut on ut.user_id = ap.promotor_id
      group by ap.store_id
    ),
    sales_today as (
      select
        s.store_id,
        coalesce(sum(s.price_at_transaction), 0)::int as omzet,
        count(*) filter (
          where coalesce(p.is_focus, false) or coalesce(p.is_fokus, false)
        )::int as focus_units
      from public.sales_sell_out s
      join public.product_variants pv on pv.id = s.variant_id
      join public.products p on p.id = pv.product_id
      where s.store_id in (select store_id from store_ids)
        and s.transaction_date = current_date
        and s.deleted_at is null
      group by s.store_id
    ),
    activity_summary as (
      select
        ap.store_id,
        count(*) filter (
          where not exists(
            select 1
            from public.attendance a
            where a.user_id = ap.promotor_id
              and a.attendance_date = current_date
              and a.clock_in is not null
          )
          or (
            (
              select count(*)::int
              from public.sales_sell_out s
              where s.promotor_id = ap.promotor_id
                and s.store_id = ap.store_id
                and s.transaction_date = current_date
                and s.deleted_at is null
            ) = 0
            and (
              select count(*)::int
              from public.stock_movement_log sml
              where sml.moved_by = ap.promotor_id
                and coalesce(sml.to_store_id, sml.from_store_id) = ap.store_id
                and (sml.moved_at at time zone 'Asia/Makassar')::date = current_date
            ) = 0
          )
        )::int as low_activity_count
      from active_promotors ap
      group by ap.store_id
    ),
    issue_summary as (
      select
        si.store_id,
        count(*)::int as issue_count
      from public.store_issues si
      where si.store_id in (select store_id from store_ids)
        and si.resolved = false
      group by si.store_id
    ),
    visit_summary as (
      select
        sv.store_id,
        count(*)::int as visit_count,
        max(sv.created_at) as last_visit
      from public.store_visits sv
      where sv.sator_id = p_sator_id
        and sv.store_id in (select store_id from store_ids)
      group by sv.store_id
    ),
    store_metrics as (
      select
        st.id as store_id,
        st.store_name,
        st.address,
        st.area,
        vs.last_visit,
        coalesce(vs.visit_count, 0) as visit_count,
        coalesce(iss.issue_count, 0) as issue_count,
        coalesce(ts.monthly_target_omzet, 0) as monthly_target_omzet,
        coalesce(sa.omzet, 0) as omzet,
        coalesce(sa.focus_units, 0) as focus_units,
        coalesce(act.low_activity_count, 0) as low_activity_count
      from public.stores st
      left join visit_summary vs on vs.store_id = st.id
      left join issue_summary iss on iss.store_id = st.id
      left join target_summary ts on ts.store_id = st.id
      left join sales_today sa on sa.store_id = st.id
      left join activity_summary act on act.store_id = st.id
      where st.id in (select store_id from store_ids)
    ),
    scored as (
      select
        sm.*,
        (
          case when sm.issue_count > 0 then 35 else 0 end +
          case when sm.visit_count = 0 then 25 else 0 end +
          case when sm.visit_count > 0 and sm.last_visit < now() - interval '7 days' then 15 else 0 end +
          case when sm.omzet < round(sm.monthly_target_omzet / 30.0) then 15 else 0 end +
          case when sm.focus_units <= 0 then 5 else 0 end +
          case when sm.low_activity_count > 0 then 10 else 0 end
        )::int as priority_score,
        array_remove(array[
          case when sm.issue_count > 0 then 'Ada issue toko yang belum selesai' end,
          case when sm.visit_count = 0 then 'Toko belum pernah divisit' end,
          case when sm.visit_count > 0 and sm.last_visit < now() - interval '7 days' then 'Sudah lama tidak divisit' end,
          case when sm.omzet < round(sm.monthly_target_omzet / 30.0) then 'Sell out di bawah target harian' end,
          case when sm.focus_units <= 0 then 'Produk fokus belum bergerak' end,
          case when sm.low_activity_count > 0 then 'Ada promotor dengan aktivitas rendah' end
        ], null) as priority_reasons
      from store_metrics sm
    )
    select coalesce(
      json_agg(
        json_build_object(
          'store_id', s.store_id,
          'store_name', s.store_name,
          'address', s.address,
          'area', s.area,
          'last_visit', s.last_visit,
          'issue_count', s.issue_count,
          'priority', case
            when s.priority_score >= 35 then 1
            when s.visit_count = 0 then 2
            when s.priority_score >= 20 then 3
            else 4
          end,
          'priority_score', s.priority_score,
          'priority_reasons', to_json(s.priority_reasons)
        )
        order by s.priority_score desc, s.store_name
      ),
      '[]'::json
    )
    from scored s
  );
end;
$function$;

grant execute on function public.get_sator_visiting_stores(uuid) to authenticated;
