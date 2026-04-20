create or replace function public.get_sator_workplace_snapshot(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_home_summary jsonb := '{}'::jsonb;
  v_profile jsonb := '{}'::jsonb;
  v_month_year text := to_char(p_date, 'YYYY-MM');
  v_schedule_pending_count integer := 0;
  v_permission_pending_count integer := 0;
  v_visiting_done boolean := false;
  v_sell_in_pending_count integer := 0;
  v_imei_pending_count integer := 0;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select jsonb_build_object(
    'full_name', coalesce(u.full_name, 'Sator'),
    'area', coalesce(u.area, '-'),
    'role', coalesce(u.role, 'sator')
  )
  into v_profile
  from public.users u
  where u.id = p_sator_id;

  v_home_summary := coalesce(public.get_sator_home_summary(p_sator_id)::jsonb, '{}'::jsonb);

  select count(*)::int
  into v_schedule_pending_count
  from public.get_sator_schedule_summary(p_sator_id, v_month_year) sch
  where sch.status = 'submitted';

  select count(*)::int
  into v_permission_pending_count
  from public.permission_requests pr
  where pr.sator_id = p_sator_id
    and pr.status = 'pending_sator';

  select exists(
    select 1
    from public.store_visits sv
    where sv.sator_id = p_sator_id
      and sv.visit_date = p_date
  )
  into v_visiting_done;

  select coalesce(json_array_length(public.get_pending_orders(p_sator_id)), 0)
  into v_sell_in_pending_count;

  select count(*)::int
  into v_imei_pending_count
  from public.imei_normalizations i
  where i.promotor_id in (
      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = p_sator_id
        and hsp.active = true
    )
    and i.normalization_status <> 'completed';

  return jsonb_build_object(
    'profile', coalesce(v_profile, '{}'::jsonb),
    'attendance_total', coalesce((v_home_summary #>> '{daily,attendance_total}')::int, 0),
    'attendance_present', coalesce((v_home_summary #>> '{daily,attendance_present}')::int, 0),
    'attendance_missing', greatest(
      coalesce((v_home_summary #>> '{daily,attendance_total}')::int, 0) -
      coalesce((v_home_summary #>> '{daily,attendance_present}')::int, 0),
      0
    ),
    'schedule_pending_count', v_schedule_pending_count,
    'permission_pending_count', v_permission_pending_count,
    'visiting_done', v_visiting_done,
    'sell_in_pending_count', v_sell_in_pending_count,
    'imei_pending_count', v_imei_pending_count,
    'chip_review_count', 0
  );
end;
$$;

grant execute on function public.get_sator_workplace_snapshot(uuid, date) to authenticated;

create or replace function public.get_sator_team_snapshot(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return (
    with promotor_scope as (
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
    latest_assignment as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        aps.store_id,
        aps.created_at
      from public.assignments_promotor_store aps
      join promotor_scope ps on ps.promotor_id = aps.promotor_id
      where aps.active = true
        and (
          not exists (select 1 from sator_store_scope)
          or aps.store_id in (select sss.store_id from sator_store_scope sss)
        )
      order by aps.promotor_id, aps.created_at desc, aps.store_id
    ),
    promotor_checklist as (
      select
        u.id,
        u.full_name,
        coalesce(u.promotor_type, 'training') as promotor_type,
        la.store_id,
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
          from public.stock_validations sv
          where sv.promotor_id = u.id
            and sv.validation_date = p_date
        ) as stock_validation,
        exists(
          select 1
          from public.allbrand_reports abr
          where abr.promotor_id = u.id
            and abr.report_date = p_date
        ) as allbrand
      from public.users u
      join latest_assignment la on la.promotor_id = u.id
    ),
    promotor_enriched as (
      select
        pc.id,
        pc.full_name,
        pc.promotor_type,
        pc.store_id,
        (
          case when pc.clock_in then 1 else 0 end +
          case when pc.sell_out then 1 else 0 end +
          case when pc.stock_validation then 1 else 0 end +
          case when pc.allbrand then 1 else 0 end
        ) as completed_tasks
      from promotor_checklist pc
    ),
    store_base as (
      select
        st.id,
        st.store_name,
        st.address
      from public.stores st
      join latest_assignment la on la.store_id = st.id
      group by st.id, st.store_name, st.address
    ),
    promotors_payload as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', pe.id,
            'full_name', pe.full_name,
            'promotor_type', pe.promotor_type,
            'store_id', sb.id,
            'store_name', sb.store_name,
            'completed_tasks', pe.completed_tasks
          )
          order by pe.full_name
        ),
        '[]'::jsonb
      ) as data
      from promotor_enriched pe
      join store_base sb on sb.id = pe.store_id
    ),
    stores_payload as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'store_id', sb.id,
            'store_name', sb.store_name,
            'address', sb.address,
            'completion_percent', coalesce((
              select round((avg((least(pe.completed_tasks, 4)::numeric / 4::numeric) * 100)))::int
              from promotor_enriched pe
              where pe.store_id = sb.id
            ), 0),
            'promotors', coalesce((
              select jsonb_agg(
                jsonb_build_object(
                  'id', pe.id,
                  'full_name', pe.full_name,
                  'promotor_type', pe.promotor_type,
                  'completed_tasks', pe.completed_tasks
                )
                order by pe.full_name
              )
              from promotor_enriched pe
              where pe.store_id = sb.id
            ), '[]'::jsonb)
          )
          order by sb.store_name
        ),
        '[]'::jsonb
      ) as data
      from store_base sb
    )
    select jsonb_build_object(
      'promotors', pp.data,
      'stores', sp.data
    )
    from promotors_payload pp
    cross join stores_payload sp
  );
end;
$$;

grant execute on function public.get_sator_team_snapshot(uuid, date) to authenticated;

create or replace function public.get_sator_laporan_kinerja_snapshot(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_summary jsonb := '{}'::jsonb;
  v_weekly jsonb := '{}'::jsonb;
  v_week_start date;
  v_week_end date;
  v_promotor_rows jsonb := '[]'::jsonb;
  v_store_rows jsonb := '[]'::jsonb;
  v_alerts jsonb := '[]'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  v_summary := coalesce(public.get_sator_home_summary(p_sator_id)::jsonb, '{}'::jsonb);
  v_weekly := coalesce(v_summary -> 'weekly', '{}'::jsonb);
  v_week_start := nullif(v_weekly ->> 'week_start', '')::date;
  v_week_end := nullif(v_weekly ->> 'week_end', '')::date;

  if v_week_start is null or v_week_end is null then
    raise exception 'Rentang minggu aktif tidak ditemukan.';
  end if;

  v_promotor_rows := coalesce((
    with promotor_scope as (
      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = p_sator_id
        and hsp.active = true
    ),
    latest_assignment as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        aps.store_id,
        aps.created_at,
        st.store_name
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      join promotor_scope ps on ps.promotor_id = aps.promotor_id
      where aps.active = true
      order by aps.promotor_id, aps.created_at desc, aps.store_id
    ),
    daily_target as (
      select
        ps.promotor_id,
        d.target_weekly_all_type,
        d.actual_weekly_all_type,
        d.target_weekly_focus,
        d.actual_weekly_focus
      from promotor_scope ps
      left join lateral public.get_daily_target_dashboard(ps.promotor_id, v_week_start) d on true
    ),
    sales_rollup as (
      select
        sso.promotor_id,
        coalesce(sum(sso.price_at_transaction), 0)::numeric as actual_weekly_omzet,
        coalesce(sum(case when p.is_focus = true then 1 else 0 end), 0)::int as focus_units
      from public.sales_sell_out sso
      left join public.product_variants pv on pv.id = sso.variant_id
      left join public.products p on p.id = pv.product_id
      where sso.promotor_id in (select promotor_id from promotor_scope)
        and sso.transaction_date >= v_week_start
        and sso.transaction_date <= v_week_end
        and sso.is_chip_sale = false
        and sso.deleted_at is null
      group by sso.promotor_id
    )
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.actual_weekly_omzet desc, x.name),
      '[]'::jsonb
    )
    from (
      select
        u.id as promotor_id,
        coalesce(u.full_name, '-') as name,
        coalesce(la.store_name, '-') as store_name,
        coalesce(dt.target_weekly_all_type, 0)::numeric as target_weekly_omzet,
        coalesce(sr.actual_weekly_omzet, 0)::numeric as actual_weekly_omzet,
        coalesce(dt.target_weekly_focus, 0)::numeric as target_weekly_focus,
        case
          when coalesce(dt.actual_weekly_focus, 0)::int > 0 then coalesce(dt.actual_weekly_focus, 0)::int
          else coalesce(sr.focus_units, 0)::int
        end as actual_weekly_focus,
        case
          when coalesce(dt.target_weekly_all_type, 0)::numeric > 0 then
            round((coalesce(sr.actual_weekly_omzet, 0)::numeric / dt.target_weekly_all_type::numeric) * 100, 1)
          else 0
        end as achievement_pct
      from public.users u
      join promotor_scope ps on ps.promotor_id = u.id
      left join latest_assignment la on la.promotor_id = u.id
      left join daily_target dt on dt.promotor_id = u.id
      left join sales_rollup sr on sr.promotor_id = u.id
    ) x
  ), '[]'::jsonb);

  v_store_rows := coalesce((
    with pr as (
      select *
      from jsonb_to_recordset(v_promotor_rows) as x(
        promotor_id uuid,
        name text,
        store_name text,
        target_weekly_omzet numeric,
        actual_weekly_omzet numeric,
        target_weekly_focus numeric,
        actual_weekly_focus integer,
        achievement_pct numeric
      )
    ),
    latest_assignment as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        aps.store_id
      from public.assignments_promotor_store aps
      join public.hierarchy_sator_promotor hsp on hsp.promotor_id = aps.promotor_id
      where hsp.sator_id = p_sator_id
        and hsp.active = true
        and aps.active = true
      order by aps.promotor_id, aps.created_at desc, aps.store_id
    )
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'store_id', la.store_id,
          'store_name', pr.store_name,
          'omzet', coalesce(sum(pr.actual_weekly_omzet), 0),
          'focus_units', coalesce(sum(pr.actual_weekly_focus), 0),
          'promotor_count', count(pr.promotor_id)::int
        )
        order by coalesce(sum(pr.actual_weekly_omzet), 0) desc, pr.store_name
      ),
      '[]'::jsonb
    )
    from pr
    join latest_assignment la on la.promotor_id = pr.promotor_id
    group by true
  ), '[]'::jsonb);

  v_alerts := coalesce((
    with pr as (
      select *
      from jsonb_to_recordset(v_promotor_rows) as x(
        promotor_id uuid,
        name text,
        store_name text,
        target_weekly_omzet numeric,
        actual_weekly_omzet numeric,
        target_weekly_focus numeric,
        actual_weekly_focus integer,
        achievement_pct numeric
      )
    ),
    sr as (
      select *
      from jsonb_to_recordset(v_store_rows) as x(
        store_id uuid,
        store_name text,
        omzet numeric,
        focus_units integer,
        promotor_count integer
      )
    )
    select coalesce(
      jsonb_agg(to_jsonb(a) order by a.idx),
      '[]'::jsonb
    )
    from (
      select 1 as idx,
        'Promotor Belum Bergerak'::text as title,
        count(*)::int as count,
        min(name) || ' dan lainnya belum ada sell out minggu ini' as note,
        'danger'::text as tone
      from pr
      where actual_weekly_omzet <= 0
      having count(*) > 0
      union all
      select 2 as idx,
        'Promotor Tertinggal'::text as title,
        count(*)::int as count,
        min(name) || ' masih jauh di bawah target minggu ini' as note,
        'warning'::text as tone
      from pr
      where achievement_pct > 0
        and achievement_pct < 40
      having count(*) > 0
      union all
      select 3 as idx,
        'Toko Perlu Atensi'::text as title,
        count(*)::int as count,
        min(store_name) || ' belum ada penjualan pada minggu aktif' as note,
        'primary'::text as tone
      from sr
      where omzet <= 0
      having count(*) > 0
    ) a
  ), '[]'::jsonb);

  return jsonb_build_object(
    'summary', v_summary,
    'promotor_rows', v_promotor_rows,
    'store_rows', v_store_rows,
    'alerts', v_alerts
  );
end;
$$;

grant execute on function public.get_sator_laporan_kinerja_snapshot(uuid, date) to authenticated;

create or replace function public.get_sator_kpi_page_snapshot(
  p_sator_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_kpi jsonb := '{}'::jsonb;
  v_kpi_detail jsonb := '{}'::jsonb;
  v_point_ranges jsonb := '[]'::jsonb;
  v_special_rewards jsonb := '[]'::jsonb;
  v_rewards jsonb := '[]'::jsonb;
  v_bonus_detail jsonb := '{}'::jsonb;
  v_components jsonb := '[]'::jsonb;
  v_period_id uuid;
  v_start_date date;
  v_end_date date;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  v_kpi := coalesce(public.get_sator_kpi_summary(p_sator_id)::jsonb, '{}'::jsonb);

  select public.get_current_target_period()::uuid
  into v_period_id;

  if v_period_id is null then
    select tp.id, tp.start_date, tp.end_date
    into v_period_id, v_start_date, v_end_date
    from public.target_periods tp
    where tp.target_month = extract(month from current_date)::int
      and tp.target_year = extract(year from current_date)::int
      and tp.deleted_at is null
    order by tp.start_date desc
    limit 1;
  else
    select tp.start_date, tp.end_date
    into v_start_date, v_end_date
    from public.target_periods tp
    where tp.id = v_period_id
    limit 1;
  end if;

  with target_row as (
    select
      coalesce(ut.target_sell_out, 0)::numeric as target_sellout,
      coalesce(ut.target_fokus, 0)::numeric as target_fokus,
      coalesce(ut.target_sell_in, 0)::numeric as target_sellin
    from public.user_targets ut
    where ut.user_id = p_sator_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc
    limit 1
  ),
  promotor_scope as (
    select hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.active = true
  ),
  metrics_rollup as (
    select
      coalesce(sum(dpm.total_omzet_real), 0)::numeric as actual_sellout,
      coalesce(sum(dpm.total_units_focus), 0)::numeric as actual_fokus
    from public.dashboard_performance_metrics dpm
    where dpm.user_id in (select promotor_id from promotor_scope)
      and dpm.period_id = v_period_id
  ),
  sellin_rollup as (
    select
      coalesce(sum(ssi.total_value), 0)::numeric as actual_sellin
    from public.sales_sell_in ssi
    where ssi.sator_id = p_sator_id
      and (v_start_date is null or ssi.transaction_date >= v_start_date)
      and (v_end_date is null or ssi.transaction_date <= v_end_date)
      and ssi.deleted_at is null
  ),
  kpi_ma_row as (
    select coalesce(km.score, 0)::numeric as kpi_ma
    from public.kpi_ma_scores km
    where km.sator_id = p_sator_id
      and km.period_date = v_start_date
    limit 1
  )
  select jsonb_build_object(
    'target_sellout', coalesce(tr.target_sellout, 0),
    'target_fokus', coalesce(tr.target_fokus, 0),
    'target_sellin', coalesce(tr.target_sellin, 0),
    'actual_sellout', coalesce(mr.actual_sellout, 0),
    'actual_fokus', coalesce(mr.actual_fokus, 0),
    'actual_sellin', coalesce(sr.actual_sellin, 0),
    'kpi_ma', coalesce(km.kpi_ma, 0)
  )
  into v_kpi_detail
  from target_row tr
  full join metrics_rollup mr on true
  full join sellin_rollup sr on true
  full join kpi_ma_row km on true;

  with kpi_settings as (
    select
      ks.kpi_name,
      coalesce(ks.weight, 0)::numeric as raw_weight
    from public.kpi_settings ks
    where ks.role = 'sator'
    order by ks.weight desc, ks.kpi_name
  ),
  totals as (
    select coalesce(sum(raw_weight), 0)::numeric as total_weight
    from kpi_settings
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', ks.kpi_name,
        'rawWeight', ks.raw_weight,
        'weight', case when t.total_weight > 0 then (ks.raw_weight * 100 / t.total_weight) else 0 end,
        'score', case
          when lower(ks.kpi_name) like '%sell out all%' then coalesce((v_kpi ->> 'sell_out_all_score')::numeric, 0)
          when lower(ks.kpi_name) like '%sell out fokus%' then coalesce((v_kpi ->> 'sell_out_fokus_score')::numeric, 0)
          when lower(ks.kpi_name) like '%sell in%' then coalesce((v_kpi ->> 'sell_in_score')::numeric, 0)
          when lower(ks.kpi_name) like '%kpi ma%' then coalesce((v_kpi ->> 'kpi_ma_score')::numeric, 0)
          else 0
        end
      )
      order by ks.raw_weight desc, ks.kpi_name
    ),
    '[]'::jsonb
  )
  into v_components
  from kpi_settings ks
  cross join totals t;

  select coalesce(jsonb_agg(to_jsonb(pr) order by pr.data_source, pr.min_price), '[]'::jsonb)
  into v_point_ranges
  from (
    select min_price, max_price, points_per_unit, data_source
    from public.point_ranges
    where role = 'sator'
    order by data_source, min_price
  ) pr;

  v_special_rewards := coalesce(public.get_special_rewards_by_role('sator')::jsonb, '[]'::jsonb);
  v_rewards := coalesce(public.get_sator_rewards(p_sator_id)::jsonb, '[]'::jsonb);
  v_bonus_detail := coalesce(public.get_sator_bonus_detail(p_sator_id)::jsonb, '{}'::jsonb);

  return jsonb_build_object(
    'kpi_data', coalesce(v_kpi, '{}'::jsonb),
    'kpi_components', v_components,
    'kpi_detail', coalesce(v_kpi_detail, '{}'::jsonb),
    'point_ranges', v_point_ranges,
    'special_rewards', v_special_rewards,
    'rewards', v_rewards,
    'bonus_detail', v_bonus_detail
  );
end;
$$;

grant execute on function public.get_sator_kpi_page_snapshot(uuid) to authenticated;

create or replace function public.get_sator_pre_visit_snapshot(
  p_sator_id uuid,
  p_store_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_store jsonb := '{}'::jsonb;
  v_comments jsonb := '[]'::jsonb;
  v_performance jsonb := '{}'::jsonb;
  v_monthly_rows jsonb := '[]'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(p_sator_id)::jsonb, '[]'::jsonb)) as x(
      store_id uuid,
      store_name text,
      address text,
      area text,
      last_visit timestamptz,
      issue_count integer,
      priority integer,
      priority_score integer,
      priority_reasons jsonb
    )
    where x.store_id = p_store_id
  ) then
    raise exception 'Store is outside SATOR scope';
  end if;

  select to_jsonb(s)
  into v_store
  from (
    select st.id, st.store_name, st.address, st.area
    from public.stores st
    where st.id = p_store_id
    limit 1
  ) s;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', svc.id,
        'comment_text', svc.comment_text,
        'created_at', svc.created_at,
        'users', jsonb_build_object(
          'full_name', coalesce(u.full_name, 'User')
        )
      )
      order by svc.created_at desc
    ),
    '[]'::jsonb
  )
  into v_comments
  from (
    select *
    from public.store_visit_comments
    where store_id = p_store_id
      and (target_sator_id = p_sator_id or author_id = p_sator_id)
    order by created_at desc
    limit 12
  ) svc
  left join public.users u on u.id = svc.author_id;

  v_performance := coalesce(public.get_sator_visiting_briefing(p_sator_id, p_store_id, p_date)::jsonb, '{}'::jsonb);
  v_monthly_rows := coalesce(public.get_sator_store_promotor_monthly_activities(p_sator_id, p_store_id, p_date)::jsonb, '[]'::jsonb);

  return (
    with monthly_rows as (
      select *
      from jsonb_to_recordset(v_monthly_rows) as x(
        promotor_id uuid,
        month_stock_input_count integer,
        month_stock_validation_count integer,
        month_sell_out_count integer,
        month_promotion_count integer,
        month_follower_count integer,
        month_allbrand_count integer,
        month_activity_days integer,
        stock_count integer
      )
    ),
    promotors as (
      select coalesce(v_performance -> 'promotors', '[]'::jsonb) as data
    ),
    merged_promotors as (
      select coalesce(
        jsonb_agg(
          to_jsonb(p) || coalesce(to_jsonb(mr), '{}'::jsonb)
          order by p.promotor_name
        ),
        '[]'::jsonb
      ) as data
      from jsonb_to_recordset((select data from promotors)) as p(
        promotor_id uuid,
        promotor_name text,
        target_nominal numeric,
        actual_nominal numeric,
        target_focus_units numeric,
        actual_focus_units numeric,
        achievement_pct numeric,
        latest_allbrand_total_units integer,
        latest_allbrand_cumulative_total_units integer,
        daily_target numeric,
        focus_target numeric,
        vast_target numeric
      )
      left join monthly_rows mr on mr.promotor_id = p.promotor_id
    )
    select jsonb_build_object(
      'store', coalesce(v_store, '{}'::jsonb),
      'comments', coalesce(v_comments, '[]'::jsonb),
      'performance', (coalesce(v_performance, '{}'::jsonb) - 'promotors') || jsonb_build_object(
        'promotors', coalesce((select data from merged_promotors), '[]'::jsonb)
      )
    )
  );
end;
$$;

grant execute on function public.get_sator_pre_visit_snapshot(uuid, uuid, date) to authenticated;

create or replace function public.create_sator_visit_comment(
  p_store_id uuid,
  p_comment_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sator_id uuid := auth.uid();
  v_row public.store_visit_comments%rowtype;
begin
  if v_sator_id is null then
    raise exception 'Authentication required';
  end if;

  if trim(coalesce(p_comment_text, '')) = '' then
    raise exception 'Comment is required';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(v_sator_id)::jsonb, '[]'::jsonb)) as x(
      store_id uuid,
      store_name text,
      address text,
      area text,
      last_visit timestamptz,
      issue_count integer,
      priority integer,
      priority_score integer,
      priority_reasons jsonb
    )
    where x.store_id = p_store_id
  ) then
    raise exception 'Store is outside SATOR scope';
  end if;

  insert into public.store_visit_comments (
    store_id,
    author_id,
    target_sator_id,
    comment_text
  )
  values (
    p_store_id,
    v_sator_id,
    v_sator_id,
    trim(p_comment_text)
  )
  returning *
  into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'comment_text', v_row.comment_text,
    'created_at', v_row.created_at
  );
end;
$$;

grant execute on function public.create_sator_visit_comment(uuid, text) to authenticated;

create or replace function public.submit_sator_visit(
  p_store_id uuid,
  p_photo_urls jsonb,
  p_notes text default null,
  p_visit_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sator_id uuid := auth.uid();
  v_visit_date date := (p_visit_at at time zone 'Asia/Makassar')::date;
  v_first_photo text;
  v_second_photo text;
  v_row public.store_visits%rowtype;
begin
  if v_sator_id is null then
    raise exception 'Authentication required';
  end if;

  if coalesce(jsonb_array_length(coalesce(p_photo_urls, '[]'::jsonb)), 0) <= 0 then
    raise exception 'Minimal 1 foto visit diperlukan.';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(coalesce(public.get_sator_visiting_stores(v_sator_id)::jsonb, '[]'::jsonb)) as x(
      store_id uuid,
      store_name text,
      address text,
      area text,
      last_visit timestamptz,
      issue_count integer,
      priority integer,
      priority_score integer,
      priority_reasons jsonb
    )
    where x.store_id = p_store_id
  ) then
    raise exception 'Store is outside SATOR scope';
  end if;

  select value
  into v_first_photo
  from jsonb_array_elements_text(coalesce(p_photo_urls, '[]'::jsonb))
  limit 1;

  select value
  into v_second_photo
  from jsonb_array_elements_text(coalesce(p_photo_urls, '[]'::jsonb))
  offset 1
  limit 1;

  insert into public.store_visits (
    store_id,
    sator_id,
    visit_date,
    check_in_time,
    check_in_photo,
    check_out_photo,
    notes,
    follow_up
  )
  values (
    p_store_id,
    v_sator_id,
    v_visit_date,
    p_visit_at,
    v_first_photo,
    v_second_photo,
    nullif(trim(coalesce(p_notes, '')), ''),
    null
  )
  returning *
  into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'visit_date', v_row.visit_date,
    'check_in_time', v_row.check_in_time
  );
end;
$$;

grant execute on function public.submit_sator_visit(uuid, jsonb, text, timestamptz) to authenticated;

create or replace function public.get_sator_sales_snapshot(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_month_key date := date_trunc('month', p_date)::date;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return (
    with promotor_scope as (
      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = p_sator_id
        and hsp.active = true
    ),
    profile as (
      select
        coalesce(u.full_name, 'SATOR') as full_name,
        coalesce(u.area, '-') as area
      from public.users u
      where u.id = p_sator_id
      limit 1
    ),
    spv_link as (
      select
        coalesce(spv.full_name, '-') as spv_name
      from public.hierarchy_spv_sator hss
      join public.users spv on spv.id = hss.spv_id
      where hss.sator_id = p_sator_id
        and hss.active = true
      order by hss.created_at desc nulls last
      limit 1
    ),
    stores_payload as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'store_id', ass.store_id,
            'store_name', st.store_name,
            'area', st.area
          )
          order by st.store_name
        ),
        '[]'::jsonb
      ) as data
      from public.assignments_sator_store ass
      join public.stores st on st.id = ass.store_id
      where ass.sator_id = p_sator_id
        and ass.active = true
    ),
    team_payload as (
      select coalesce(public.get_users_with_hierarchy(p_sator_id, 'sator')::jsonb, '[]'::jsonb) as data
    ),
    daily_feed as (
      select coalesce(
        jsonb_agg(to_jsonb(vd) order by vd.total_submissions desc, vd.promotor_name),
        '[]'::jsonb
      ) as data
      from public.vast_agg_daily_promotor vd
      where vd.metric_date = p_date
        and vd.promotor_id in (select promotor_id from promotor_scope)
    ),
    monthly_feed as (
      select coalesce(
        jsonb_agg(to_jsonb(vm) order by vm.total_submissions desc, vm.promotor_name),
        '[]'::jsonb
      ) as data
      from public.vast_agg_monthly_promotor vm
      where vm.month_key = v_month_key
        and vm.promotor_id in (select promotor_id from promotor_scope)
    )
    select jsonb_build_object(
      'profile', coalesce((select to_jsonb(p) from profile p), '{}'::jsonb),
      'spv_name', coalesce((select spv_name from spv_link), '-'),
      'stores', coalesce((select data from stores_payload), '[]'::jsonb),
      'team_members', coalesce((select data from team_payload), '[]'::jsonb),
      'daily_feed', coalesce((select data from daily_feed), '[]'::jsonb),
      'monthly_feed', coalesce((select data from monthly_feed), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_sator_sales_snapshot(uuid, date) to authenticated;

create or replace function public.format_shift_time_range(
  p_start time,
  p_end time
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when p_start is null or p_end is null then '-'
    else to_char(p_start, 'HH24:MI') || '-' || to_char(p_end, 'HH24:MI')
  end;
$$;

grant execute on function public.format_shift_time_range(time, time) to authenticated;

create or replace function public.sum_allbrand_brand_units(p_data jsonb)
returns integer
language sql
immutable
set search_path = public
as $$
  select coalesce(sum(
    coalesce(nullif(value ->> 'under_2m', '')::int, 0) +
    coalesce(nullif(value ->> '2m_4m', '')::int, 0) +
    coalesce(nullif(value ->> '4m_6m', '')::int, 0) +
    coalesce(nullif(value ->> 'above_6m', '')::int, 0)
  ), 0)::int
  from jsonb_each(case when jsonb_typeof(coalesce(p_data, '{}'::jsonb)) = 'object' then p_data else '{}'::jsonb end);
$$;

grant execute on function public.sum_allbrand_brand_units(jsonb) to authenticated;

create or replace function public.format_allbrand_brand_units(p_data jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(
    key || ':' || (
      coalesce(nullif(value ->> 'under_2m', '')::int, 0) +
      coalesce(nullif(value ->> '2m_4m', '')::int, 0) +
      coalesce(nullif(value ->> '4m_6m', '')::int, 0) +
      coalesce(nullif(value ->> 'above_6m', '')::int, 0)
    )::text,
    ' | ' order by key
  ), '')
  from jsonb_each(case when jsonb_typeof(coalesce(p_data, '{}'::jsonb)) = 'object' then p_data else '{}'::jsonb end);
$$;

grant execute on function public.format_allbrand_brand_units(jsonb) to authenticated;

create or replace function public.format_allbrand_simple_counts(p_data jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(
    key || ':' || coalesce(nullif(value::text, '')::int, 0)::text,
    ' | ' order by key
  ), '')
  from jsonb_each_text(case when jsonb_typeof(coalesce(p_data, '{}'::jsonb)) = 'object' then p_data else '{}'::jsonb end);
$$;

grant execute on function public.format_allbrand_simple_counts(jsonb) to authenticated;

create or replace function public.get_export_schedule_snapshot(
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
    raise exception 'Role ini belum didukung untuk export jadwal.';
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
    promotor_scope as (
      select distinct
        case
          when v_actor_role = 'sator' then aps.promotor_id
          else hsp.promotor_id
        end as promotor_id,
        ss.sator_name
      from sator_scope ss
      left join public.assignments_sator_store ass
        on v_actor_role = 'sator'
       and ass.sator_id = ss.sator_id
       and ass.active = true
      left join public.assignments_promotor_store aps
        on v_actor_role = 'sator'
       and aps.store_id = ass.store_id
       and aps.active = true
      left join public.hierarchy_sator_promotor hsp
        on v_actor_role = 'spv'
       and hsp.sator_id = ss.sator_id
       and hsp.active = true
    ),
    promotor_profile as (
      select
        u.id as promotor_id,
        coalesce(u.full_name, 'Unknown') as promotor_name,
        coalesce(u.area, 'default') as area,
        ps.sator_name,
        coalesce((
          select string_agg(distinct st.store_name, ', ' order by st.store_name)
          from public.assignments_promotor_store aps
          join public.stores st on st.id = aps.store_id
          where aps.promotor_id = u.id
            and aps.active = true
        ), '-') as store_names
      from promotor_scope ps
      join public.users u on u.id = ps.promotor_id
    ),
    schedules_scope as (
      select
        s.promotor_id,
        s.schedule_date,
        coalesce(s.shift_type, '-') as shift_type,
        coalesce(s.status, 'belum_kirim') as status,
        case
          when lower(coalesce(s.shift_type, '')) = 'libur' then 'Libur'
          when lower(coalesce(s.shift_type, '')) = 'fullday' then coalesce(
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = pp.area
                and lower(ss.shift_type) = 'fullday'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = 'default'
                and lower(ss.shift_type) = 'fullday'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            '08:00-22:00'
          )
          else coalesce(
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = pp.area
                and lower(ss.shift_type) = lower(s.shift_type)
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = 'default'
                and lower(ss.shift_type) = lower(s.shift_type)
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            '-'
          )
        end as shift_time
      from public.schedules s
      join promotor_profile pp on pp.promotor_id = s.promotor_id
      where s.schedule_date >= p_start_date
        and s.schedule_date <= p_end_date
    ),
    rows_payload as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', pp.promotor_id,
            'promotor_name', pp.promotor_name,
            'store_names', pp.store_names,
            'sator_name', pp.sator_name,
            'status', coalesce((
              select upper(ss.status)
              from schedules_scope ss
              where ss.promotor_id = pp.promotor_id
              order by ss.schedule_date desc
              limit 1
            ), 'BELUM_KIRIM'),
            'schedule_map', coalesce((
              select jsonb_object_agg(
                to_char(ss.schedule_date, 'YYYY-MM-DD'),
                upper(ss.shift_type) || E'\n' || ss.shift_time
              )
              from schedules_scope ss
              where ss.promotor_id = pp.promotor_id
            ), '{}'::jsonb)
          )
          order by pp.promotor_name
        ),
        '[]'::jsonb
      ) as data
      from promotor_profile pp
    ),
    legend_payload as (
      select jsonb_agg(
        jsonb_build_object(
          'shift', x.shift,
          'time', x.time
        )
        order by x.sort_order
      ) as data
      from (
        select 1 as sort_order, 'PAGI'::text as shift, coalesce(string_agg(distinct t.time_text, ' / ' order by t.time_text), '-') as time
        from (
          select coalesce(
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = pp.area
                and lower(ss.shift_type) = 'pagi'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = 'default'
                and lower(ss.shift_type) = 'pagi'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            '-'
          ) as time_text
          from promotor_profile pp
        ) t
        union all
        select 2 as sort_order, 'SIANG'::text as shift, coalesce(string_agg(distinct t.time_text, ' / ' order by t.time_text), '-') as time
        from (
          select coalesce(
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = pp.area
                and lower(ss.shift_type) = 'siang'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = 'default'
                and lower(ss.shift_type) = 'siang'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            '-'
          ) as time_text
          from promotor_profile pp
        ) t
        union all
        select 3 as sort_order, 'FULLDAY'::text as shift, coalesce(string_agg(distinct t.time_text, ' / ' order by t.time_text), '08:00-22:00') as time
        from (
          select coalesce(
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = pp.area
                and lower(ss.shift_type) = 'fullday'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            (
              select public.format_shift_time_range(ss.start_time, ss.end_time)
              from public.shift_settings ss
              where ss.area = 'default'
                and lower(ss.shift_type) = 'fullday'
                and ss.active = true
              order by ss.updated_at desc nulls last, ss.created_at desc nulls last
              limit 1
            ),
            '08:00-22:00'
          ) as time_text
          from promotor_profile pp
        ) t
        union all
        select 4 as sort_order, 'LIBUR'::text as shift, 'Libur'::text as time
      ) x
    )
    select jsonb_build_object(
      'rows', coalesce((select data from rows_payload), '[]'::jsonb),
      'legend', coalesce((select data from legend_payload), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_export_schedule_snapshot(date, date) to authenticated;

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
    promotor_scope as (
      select distinct
        case
          when v_actor_role = 'sator' then aps.promotor_id
          else hsp.promotor_id
        end as promotor_id,
        ss.sator_name
      from sator_scope ss
      left join public.assignments_sator_store ass
        on v_actor_role = 'sator'
       and ass.sator_id = ss.sator_id
       and ass.active = true
      left join public.assignments_promotor_store aps
        on v_actor_role = 'sator'
       and aps.store_id = ass.store_id
       and aps.active = true
      left join public.hierarchy_sator_promotor hsp
        on v_actor_role = 'spv'
       and hsp.sator_id = ss.sator_id
       and hsp.active = true
    ),
    promotor_profile as (
      select
        ps.promotor_id,
        coalesce(u.full_name, 'Unknown') as promotor_name,
        ps.sator_name
      from promotor_scope ps
      join public.users u on u.id = ps.promotor_id
    ),
    report_scope as (
      select
        ar.promotor_id,
        ar.store_id,
        ar.report_date,
        ar.created_at,
        ar.updated_at,
        coalesce(ar.brand_data_daily, ar.brand_data, '{}'::jsonb) as brand_data_daily,
        coalesce(ar.brand_data, '{}'::jsonb) as brand_data,
        coalesce(ar.leasing_sales_daily, ar.leasing_sales, '{}'::jsonb) as leasing_sales_daily,
        coalesce(ar.leasing_sales, '{}'::jsonb) as leasing_sales,
        coalesce(ar.daily_total_units, 0)::int as daily_total_units,
        coalesce(ar.cumulative_total_units, 0)::int as cumulative_total_units,
        coalesce(ar.vivo_auto_data, '{}'::jsonb) as vivo_auto_data,
        coalesce(ar.vivo_promotor_count, 0)::int as vivo_promotor_count,
        coalesce(ar.notes, '') as notes,
        coalesce(ar.status, '-') as status
      from public.allbrand_reports ar
      where ar.promotor_id in (select promotor_id from promotor_scope)
        and ar.report_date >= p_start_date
        and ar.report_date <= p_end_date
    ),
    store_names as (
      select
        st.id as store_id,
        coalesce(st.store_name, '-') as store_name
      from public.stores st
      where st.id in (select distinct store_id from report_scope)
    ),
    sales_rollup as (
      select
        sso.store_id,
        sso.transaction_date,
        count(*)::int as vivo_units
      from public.sales_sell_out sso
      where sso.store_id in (select distinct store_id from report_scope)
        and sso.transaction_date <= p_end_date
        and sso.deleted_at is null
      group by sso.store_id, sso.transaction_date
    ),
    sales_cumulative as (
      select
        sr.store_id,
        sr.transaction_date,
        sum(sr.vivo_units) over (
          partition by sr.store_id
          order by sr.transaction_date
          rows between unbounded preceding and current row
        )::int as vivo_cumulative
      from sales_rollup sr
    ),
    rows_payload as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'report_date', rs.report_date,
            'promotor_name', pp.promotor_name,
            'store_name', coalesce(sn.store_name, '-'),
            'sator_name', pp.sator_name,
            'status', rs.status,
            'edited', case
              when rs.created_at is not null and rs.updated_at is not null and rs.updated_at > rs.created_at then 'YA'
              else 'TIDAK'
            end,
            'vivo_today', coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0),
            'vivo_cumulative', coalesce(sc.vivo_cumulative, coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0), 0),
            'competitor_today', case
              when rs.daily_total_units > 0 then rs.daily_total_units
              else public.sum_allbrand_brand_units(rs.brand_data_daily)
            end,
            'competitor_cumulative', case
              when rs.cumulative_total_units > 0 then rs.cumulative_total_units
              else public.sum_allbrand_brand_units(rs.brand_data)
            end,
            'total_store_today',
            coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0) +
              case when rs.daily_total_units > 0 then rs.daily_total_units else public.sum_allbrand_brand_units(rs.brand_data_daily) end,
            'total_store_cumulative',
            coalesce(sc.vivo_cumulative, coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0), 0) +
              case when rs.cumulative_total_units > 0 then rs.cumulative_total_units else public.sum_allbrand_brand_units(rs.brand_data) end,
            'ms',
            case
              when (
                coalesce(sc.vivo_cumulative, coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0), 0) +
                case when rs.cumulative_total_units > 0 then rs.cumulative_total_units else public.sum_allbrand_brand_units(rs.brand_data) end
              ) > 0
              then round((
                coalesce(sc.vivo_cumulative, coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0), 0)::numeric * 100
              ) / (
                coalesce(sc.vivo_cumulative, coalesce(sr.vivo_units, coalesce(nullif(rs.vivo_auto_data ->> 'total', '')::int, 0), 0), 0) +
                case when rs.cumulative_total_units > 0 then rs.cumulative_total_units else public.sum_allbrand_brand_units(rs.brand_data) end
              )::numeric, 1)
              else 0
            end,
            'vivo_promotor_count', rs.vivo_promotor_count,
            'brand_daily_text', public.format_allbrand_brand_units(rs.brand_data_daily),
            'brand_cumulative_text', public.format_allbrand_brand_units(rs.brand_data),
            'leasing_daily_text', public.format_allbrand_simple_counts(rs.leasing_sales_daily),
            'leasing_cumulative_text', public.format_allbrand_simple_counts(rs.leasing_sales),
            'notes', rs.notes
          )
          order by rs.report_date desc, pp.promotor_name, coalesce(sn.store_name, '-')
        ),
        '[]'::jsonb
      ) as data
      from report_scope rs
      join promotor_profile pp on pp.promotor_id = rs.promotor_id
      left join store_names sn on sn.store_id = rs.store_id
      left join sales_rollup sr
        on sr.store_id = rs.store_id
       and sr.transaction_date = rs.report_date
      left join sales_cumulative sc
        on sc.store_id = rs.store_id
       and sc.transaction_date = rs.report_date
    )
    select jsonb_build_object(
      'rows', coalesce((select data from rows_payload), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_export_allbrand_snapshot(date, date) to authenticated;

create or replace function public.get_schedule_detail_snapshot(
  p_promotor_id uuid,
  p_month_year text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_has_access boolean := false;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    raise exception 'User profile not found';
  end if;

  if v_actor.role = 'admin' or public.is_elevated_user() then
    v_has_access := true;
  elsif v_actor.role = 'promotor' then
    v_has_access := p_promotor_id = v_actor_id;
  elsif v_actor.role = 'sator' then
    select exists(
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = v_actor_id
        and hsp.promotor_id = p_promotor_id
        and hsp.active = true
    )
    into v_has_access;
  elsif v_actor.role = 'spv' then
    select exists(
      select 1
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
        and hsp.active = true
        and hsp.promotor_id = p_promotor_id
    )
    into v_has_access;
  end if;

  if not v_has_access then
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'current_user', jsonb_build_object(
      'id', v_actor.id,
      'full_name', coalesce(v_actor.full_name, 'User'),
      'role', coalesce(v_actor.role, '')
    ),
    'schedules', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.schedule_date)
      from public.get_promotor_schedule_detail(p_promotor_id, p_month_year) s
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'author_id', c.author_id,
          'author_name', c.author_name,
          'author_role', c.author_role,
          'message', c.message,
          'created_at', c.created_at
        )
        order by c.created_at
      )
      from public.schedule_review_comments c
      where c.promotor_id = p_promotor_id
        and c.month_year = p_month_year
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_schedule_detail_snapshot(uuid, text) to authenticated;

create or replace function public.add_schedule_review_comment(
  p_promotor_id uuid,
  p_month_year text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_message text := nullif(trim(coalesce(p_message, '')), '');
  v_has_access boolean := false;
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  if v_message is null then
    return jsonb_build_object('success', false, 'message', 'Komentar tidak boleh kosong.');
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Profil user tidak ditemukan.');
  end if;

  if v_actor.role = 'admin' or public.is_elevated_user() then
    v_has_access := true;
  elsif v_actor.role = 'promotor' then
    v_has_access := p_promotor_id = v_actor_id;
  elsif v_actor.role = 'sator' then
    select exists(
      select 1
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = v_actor_id
        and hsp.promotor_id = p_promotor_id
        and hsp.active = true
    )
    into v_has_access;
  elsif v_actor.role = 'spv' then
    select exists(
      select 1
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
      where hss.spv_id = v_actor_id
        and hss.active = true
        and hsp.active = true
        and hsp.promotor_id = p_promotor_id
    )
    into v_has_access;
  end if;

  if not v_has_access then
    return jsonb_build_object('success', false, 'message', 'Anda tidak punya akses ke jadwal ini.');
  end if;

  insert into public.schedule_review_comments (
    promotor_id,
    month_year,
    author_id,
    author_name,
    author_role,
    message
  )
  values (
    p_promotor_id,
    p_month_year,
    v_actor_id,
    coalesce(v_actor.full_name, 'User'),
    coalesce(v_actor.role, 'user'),
    v_message
  );

  return jsonb_build_object('success', true, 'message', 'Komentar berhasil dikirim.');
end;
$$;

grant execute on function public.add_schedule_review_comment(uuid, text, text) to authenticated;

create or replace function public.review_monthly_schedule_with_comment(
  p_promotor_id uuid,
  p_month_year text,
  p_action text,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_result record;
  v_reason text := nullif(trim(coalesce(p_rejection_reason, '')), '');
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  select *
  into v_actor
  from public.users
  where id = v_actor_id;

  if not found or coalesce(v_actor.role, '') <> 'sator' then
    return jsonb_build_object('success', false, 'message', 'Hanya sator yang dapat mereview jadwal.');
  end if;

  select *
  into v_result
  from public.review_monthly_schedule(
    v_actor_id,
    p_promotor_id,
    p_month_year,
    p_action,
    v_reason
  )
  limit 1;

  if coalesce(v_result.success, false) <> true then
    return jsonb_build_object(
      'success', false,
      'message', coalesce(v_result.message, 'Review jadwal gagal.')
    );
  end if;

  if p_action = 'reject' and v_reason is not null then
    insert into public.schedule_review_comments (
      promotor_id,
      month_year,
      author_id,
      author_name,
      author_role,
      message
    )
    values (
      p_promotor_id,
      p_month_year,
      v_actor_id,
      coalesce(v_actor.full_name, 'SATOR'),
      coalesce(v_actor.role, 'sator'),
      v_reason
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'message', coalesce(v_result.message, 'Proses review selesai.')
  );
end;
$$;

grant execute on function public.review_monthly_schedule_with_comment(uuid, text, text, text) to authenticated;

create or replace function public.get_sator_chip_approval_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'sator' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'requests',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'reason', r.reason,
          'status', r.status,
          'requested_at', r.requested_at,
          'rejection_note', r.rejection_note,
          'request_type', r.request_type,
          'promotor_name', coalesce(p.full_name, 'Promotor'),
          'store_name', coalesce(st.store_name, '-'),
          'imei', s.imei,
          'variant', trim(concat_ws(' ', pv.ram_rom, pv.color)),
          'product_name', coalesce(pr.model_name, '-'),
          'network_type', coalesce(pr.network_type, '-')
        )
        order by r.requested_at desc
      )
      from public.stock_chip_requests r
      left join public.users p
        on p.id = r.promotor_id
      left join public.stores st
        on st.id = r.store_id
      left join public.stok s
        on s.id = r.stok_id
      left join public.product_variants pv
        on pv.id = s.variant_id
      left join public.products pr
        on pr.id = pv.product_id
      where r.sator_id = v_actor_id
      limit 200
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_sator_chip_approval_snapshot() to authenticated;

create or replace function public.get_sator_permission_approval_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'sator' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'requests',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pr.id,
          'request_date', pr.request_date,
          'request_type', pr.request_type,
          'reason', pr.reason,
          'note', pr.note,
          'photo_url', pr.photo_url,
          'status', pr.status,
          'created_at', pr.created_at,
          'sator_comment', pr.sator_comment,
          'spv_comment', pr.spv_comment,
          'promotor_name', coalesce(u.full_name, 'Promotor'),
          'spv_name', coalesce(spv.full_name, 'SPV')
        )
        order by pr.created_at desc
      )
      from public.permission_requests pr
      left join public.users u
        on u.id = pr.promotor_id
      left join public.users spv
        on spv.id = pr.spv_id
      where pr.sator_id = v_actor_id
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_sator_permission_approval_snapshot() to authenticated;

create or replace function public.get_my_profile_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  return coalesce((
    select jsonb_build_object(
      'id', u.id,
      'full_name', coalesce(u.full_name, 'User'),
      'role', coalesce(u.role, 'user'),
      'area', coalesce(u.area, '-'),
      'avatar_url', coalesce(u.avatar_url, '')
    )
    from public.users u
    where u.id = v_actor_id
  ), '{}'::jsonb);
end;
$$;

grant execute on function public.get_my_profile_snapshot() to authenticated;

create or replace function public.update_my_avatar_url(
  p_avatar_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_avatar_url text := nullif(trim(coalesce(p_avatar_url, '')), '');
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  if v_avatar_url is null then
    return jsonb_build_object('success', false, 'message', 'URL avatar tidak valid.');
  end if;

  update public.users
  set avatar_url = v_avatar_url,
      updated_at = now()
  where id = v_actor_id;

  return jsonb_build_object('success', true, 'message', 'Foto profil berhasil diperbarui.');
end;
$$;

grant execute on function public.update_my_avatar_url(text) to authenticated;

create or replace function public.get_sator_stock_management_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'sator' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'rows',
    coalesce((
      with promotor_scope as (
        select hsp.promotor_id
        from public.hierarchy_sator_promotor hsp
        where hsp.sator_id = v_actor_id
          and hsp.active = true
      )
      select jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'imei', s.imei,
          'tipe_stok', s.tipe_stok,
          'is_sold', s.is_sold,
          'promotor_name', coalesce(u.full_name, 'Promotor'),
          'store_name', coalesce(st.store_name, '-')
        )
        order by s.created_at desc
      )
      from public.stok s
      left join public.users u
        on u.id = s.promotor_id
      left join public.stores st
        on st.id = s.store_id
      where s.promotor_id in (select promotor_id from promotor_scope)
      limit 200
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_sator_stock_management_snapshot() to authenticated;

create or replace function public.get_my_chat_unread_count()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_total integer := 0;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select coalesce(sum(coalesce(r.unread_count, 0)), 0)::int
  into v_total
  from public.get_user_chat_rooms(v_actor_id) r;

  return jsonb_build_object('unread_count', v_total);
end;
$$;

grant execute on function public.get_my_chat_unread_count() to authenticated;

create or replace function public.get_store_detail_snapshot(
  p_store_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_store jsonb := '{}'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select to_jsonb(st.*)
  into v_store
  from public.stores st
  where st.id = p_store_id
    and st.deleted_at is null;

  if v_store is null then
    raise exception 'Toko tidak ditemukan atau sudah tidak aktif.';
  end if;

  return jsonb_build_object(
    'store', v_store,
    'promotors', coalesce((
      select jsonb_agg(to_jsonb(c))
      from public.get_store_promotor_checklist(
        p_store_id,
        to_char(p_date, 'YYYY-MM-DD')
      ) c
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_store_detail_snapshot(uuid, date) to authenticated;

create or replace function public.get_active_product_variant_catalog()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return jsonb_build_object(
    'items',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'variant_id', pv.id,
          'product_id', p.id,
          'product_name', coalesce(p.model_name, ''),
          'network_type', coalesce(p.network_type, ''),
          'series', coalesce(p.series, ''),
          'variant', coalesce(pv.ram_rom, ''),
          'color', coalesce(pv.color, ''),
          'price', coalesce(pv.srp, 0),
          'status', coalesce(p.status, 'active')
        )
        order by pv.id
      )
      from public.product_variants pv
      join public.products p
        on p.id = pv.product_id
      where pv.active = true
        and coalesce(p.status, 'active') = 'active'
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_active_product_variant_catalog() to authenticated;

create or replace function public.get_sator_sellin_store_options()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  return jsonb_build_object(
    'stores',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'store_id', x.store_id,
          'store_name', x.store_name
        )
        order by x.store_name
      )
      from (
        select distinct
          ssi.store_id,
          coalesce(st.store_name, 'Toko') as store_name
        from public.sales_sell_in ssi
        left join public.stores st
          on st.id = ssi.store_id
        where ssi.sator_id = v_actor_id
          and ssi.deleted_at is null
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.get_sator_sellin_store_options() to authenticated;
