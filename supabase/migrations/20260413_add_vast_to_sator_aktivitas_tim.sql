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
        coalesce((
          select case
            when a.main_attendance_status = 'late' then 'late'
            when a.clock_in is not null then 'normal'
            else ''
          end
          from public.attendance a
          where a.user_id = u.id
            and a.attendance_date = p_date
            and a.clock_in is not null
          order by a.created_at desc
          limit 1
        ), '') as attendance_category,
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
          where sv.store_id = pa.store_id
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
          where abr.store_id = pa.store_id
            and abr.report_date = p_date
        ) as allbrand,
        exists(
          select 1
          from public.vast_applications va
          where va.promotor_id = u.id
            and va.application_date = p_date
            and va.deleted_at is null
        ) as vast
      from public.users u
      join promotor_ids pi on pi.promotor_id = u.id
      join promotor_assignments pa on pa.promotor_id = u.id
    ),
    promotor_enriched as (
      select
        pc.*,
        (
          case when pc.clock_in then 1 else 0 end +
          case when pc.sell_out then 1 else 0 end +
          case when pc.stock_input then 1 else 0 end +
          case when pc.stock_validation then 1 else 0 end +
          case when pc.promotion then 1 else 0 end +
          case when pc.follower then 1 else 0 end +
          case when pc.allbrand then 1 else 0 end +
          case when pc.vast then 1 else 0 end
        ) as completed_tasks
      from promotor_checklist pc
    ),
    store_summary as (
      select
        sd.store_id,
        sd.store_name,
        count(pe.promotor_id)::int as total_promotors,
        count(*) filter (where pe.completed_tasks > 0)::int as active_promotors,
        count(*) filter (where pe.completed_tasks < 2)::int as attention_promotors,
        coalesce(sum(pe.completed_tasks), 0)::int as completed_tasks,
        (count(pe.promotor_id) * 8)::int as total_tasks,
        case
          when count(pe.promotor_id) = 0 then 0
          else round((coalesce(sum(pe.completed_tasks), 0)::numeric / (count(pe.promotor_id) * 8)::numeric) * 100)::int
        end as completion_percent
      from store_data sd
      left join promotor_enriched pe on pe.store_id = sd.store_id
      group by sd.store_id, sd.store_name
    ),
    stores_payload as (
      select coalesce(
        json_agg(
          json_build_object(
            'store_id', ss.store_id,
            'store_name', ss.store_name,
            'total_promotors', ss.total_promotors,
            'active_promotors', ss.active_promotors,
            'attention_promotors', ss.attention_promotors,
            'completed_tasks', ss.completed_tasks,
            'total_tasks', ss.total_tasks,
            'completion_percent', ss.completion_percent,
            'promotors', (
              select coalesce(
                json_agg(
                  json_build_object(
                    'id', pe.promotor_id,
                    'name', pe.name,
                    'clock_in', pe.clock_in,
                    'attendance_category', pe.attendance_category,
                    'sell_out', pe.sell_out,
                    'stock_input', pe.stock_input,
                    'stock_validation', pe.stock_validation,
                    'promotion', pe.promotion,
                    'follower', pe.follower,
                    'allbrand', pe.allbrand,
                    'vast', pe.vast,
                    'completed_tasks', pe.completed_tasks,
                    'completion_percent', round((pe.completed_tasks::numeric / 8::numeric) * 100)::int
                  )
                  order by pe.name
                ),
                '[]'::json
              )
              from promotor_enriched pe
              where pe.store_id = ss.store_id
            )
          )
          order by ss.store_name
        ),
        '[]'::json
      ) as stores
      from store_summary ss
    ),
    summary_payload as (
      select json_build_object(
        'total_stores', count(*)::int,
        'total_promotors', coalesce(sum(ss.total_promotors), 0)::int,
        'active_promotors', coalesce(sum(ss.active_promotors), 0)::int,
        'completed_tasks', coalesce(sum(ss.completed_tasks), 0)::int,
        'total_tasks', coalesce(sum(ss.total_tasks), 0)::int,
        'attention_stores', count(*) filter (where ss.attention_promotors > 0)::int
      ) as summary
      from store_summary ss
    )
    select json_build_object(
      'summary', sp.summary,
      'stores', stp.stores
    )
    from summary_payload sp
    cross join stores_payload stp
  );
end;
$$;

grant execute on function public.get_sator_aktivitas_tim(uuid, date) to authenticated;
