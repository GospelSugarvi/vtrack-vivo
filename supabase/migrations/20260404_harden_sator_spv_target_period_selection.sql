do $$
declare
  v_sql text;
begin
  select pg_get_functiondef(p.oid)
  into v_sql
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_sator_vast_page_snapshot'
    and pg_get_function_identity_arguments(p.oid) = 'p_date date';

  if v_sql is null then
    raise exception 'Function public.get_sator_vast_page_snapshot(date) not found';
  end if;

  v_sql := replace(
    v_sql,
    $old$    active_period as (
      select tp.id
      from public.target_periods tp
      where tp.status = 'active'
        and tp.deleted_at is null
      order by tp.target_year desc, tp.target_month desc, tp.created_at desc
      limit 1
    ),$old$,
    $new$    current_period as (
      select public.get_current_target_period() as id
    ),$new$
  );
  v_sql := replace(
    v_sql,
    'join active_period ap on ap.id = ut.period_id',
    'join current_period cp on cp.id = ut.period_id'
  );

  execute v_sql;
end
$$;

do $$
declare
  v_sql text;
begin
  select pg_get_functiondef(p.oid)
  into v_sql
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_spv_vast_page_snapshot'
    and pg_get_function_identity_arguments(p.oid) = 'p_date date';

  if v_sql is null then
    raise exception 'Function public.get_spv_vast_page_snapshot(date) not found';
  end if;

  v_sql := replace(
    v_sql,
    $old$    active_period as (
      select tp.id
      from public.target_periods tp
      where tp.status = 'active'
        and tp.deleted_at is null
      order by tp.target_year desc, tp.target_month desc, tp.created_at desc
      limit 1
    ),$old$,
    $new$    current_period as (
      select public.get_current_target_period() as id
    ),$new$
  );
  v_sql := replace(
    v_sql,
    'join active_period ap on ap.id = ut.period_id',
    'join current_period cp on cp.id = ut.period_id'
  );

  execute v_sql;
end
$$;

do $$
declare
  v_sql text;
begin
  select pg_get_functiondef(p.oid)
  into v_sql
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_sator_sellin_summary'
    and pg_get_function_identity_arguments(p.oid) = 'p_sator_id uuid';

  if v_sql is null then
    raise exception 'Function public.get_sator_sellin_summary(uuid) not found';
  end if;

  v_sql := replace(
    v_sql,
    $old$  WITH current_period AS (
    SELECT tp.id
    FROM public.target_periods tp
    WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
      AND COALESCE(tp.status, 'active') = 'active'
    ORDER BY tp.start_date DESC
    LIMIT 1
  ),$old$,
    $new$  WITH current_period AS (
    SELECT tp.id
    FROM public.target_periods tp
    WHERE CURRENT_DATE BETWEEN tp.start_date AND tp.end_date
      AND tp.deleted_at IS NULL
    ORDER BY tp.start_date DESC, tp.created_at DESC
    LIMIT 1
  ),$new$
  );

  execute v_sql;
end
$$;

do $$
declare
  v_sql text;
begin
  select pg_get_functiondef(p.oid)
  into v_sql
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_spv_sellin_monitor'
    and pg_get_function_identity_arguments(p.oid) = 'p_spv_id uuid, p_filter text, p_start_date date, p_end_date date';

  if v_sql is null then
    raise exception 'Function public.get_spv_sellin_monitor(uuid, text, date, date) not found';
  end if;

  v_sql := replace(
    v_sql,
    '  ORDER BY CASE WHEN tp.status = ''active'' THEN 0 ELSE 1 END, tp.start_date DESC',
    '  ORDER BY tp.start_date DESC, tp.created_at DESC'
  );

  execute v_sql;
end
$$;

do $$
declare
  v_sql text;
begin
  select pg_get_functiondef(p.oid)
  into v_sql
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_spv_sellout_monitor'
    and pg_get_function_identity_arguments(p.oid) = 'p_spv_id uuid, p_filter text, p_start_date date, p_end_date date';

  if v_sql is null then
    raise exception 'Function public.get_spv_sellout_monitor(uuid, text, date, date) not found';
  end if;

  v_sql := replace(
    v_sql,
    '  ORDER BY CASE WHEN tp.status = ''active'' THEN 0 ELSE 1 END, tp.start_date DESC',
    '  ORDER BY tp.start_date DESC, tp.created_at DESC'
  );

  execute v_sql;
end
$$;
