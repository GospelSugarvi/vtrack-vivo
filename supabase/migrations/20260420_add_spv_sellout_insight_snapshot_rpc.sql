create or replace function public.get_spv_sellout_insight_snapshot(
  p_spv_id uuid,
  p_reference_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_current_start date := date_trunc('month', p_reference_date)::date;
  v_current_end date := p_reference_date;
  v_prev_start date := (date_trunc('month', p_reference_date) - interval '1 month')::date;
  v_prev_month_last_day date := (date_trunc('month', p_reference_date)::date - 1);
  v_prev_day int;
  v_prev_end date;
  v_current_period_id uuid;
  v_prev_period_id uuid;
  v_payload jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_spv_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  v_prev_day := least(
    extract(day from p_reference_date)::int,
    extract(day from v_prev_month_last_day)::int
  );
  v_prev_end := (v_prev_start + make_interval(days => v_prev_day - 1))::date;

  select tp.id
  into v_current_period_id
  from public.target_periods tp
  where tp.deleted_at is null
    and tp.start_date <= v_current_end
    and tp.end_date >= v_current_end
  order by tp.start_date desc
  limit 1;

  select tp.id
  into v_prev_period_id
  from public.target_periods tp
  where tp.deleted_at is null
    and tp.start_date <= v_prev_end
    and tp.end_date >= v_prev_end
  order by tp.start_date desc
  limit 1;

  with sator_scope as (
    select hs.sator_id
    from public.hierarchy_spv_sator hs
    where hs.spv_id = p_spv_id
      and hs.active = true
  ),
  promotor_scope as (
    select
      hsp.sator_id,
      hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    join sator_scope ss on ss.sator_id = hsp.sator_id
    where hsp.active = true
  ),
  profile as (
    select u.full_name, u.nickname
    from public.users u
    where u.id = p_spv_id
    limit 1
  ),
  promotor_rows as (
    select
      ps.promotor_id as id,
      ps.sator_id,
      coalesce(nullif(su.full_name, ''), nullif(su.nickname, ''), 'Sator') as sator_name,
      coalesce(nullif(pu.nickname, ''), pu.full_name, 'Promotor') as name,
      coalesce(store_pick.store_name, 'Belum ada toko') as store_name,
      coalesce(
        public.get_promotor_sellout_insight(ps.promotor_id, v_current_start, v_current_end),
        '{}'::jsonb
      ) as current_insight,
      coalesce(
        public.get_promotor_sellout_insight(ps.promotor_id, v_prev_start, v_prev_end),
        '{}'::jsonb
      ) as previous_insight,
      coalesce(
        (
          select to_jsonb(ut) - 'id' - 'user_id' - 'period_id' - 'created_at' - 'updated_at'
          from public.user_targets ut
          where ut.user_id = ps.promotor_id
            and ut.period_id = v_current_period_id
          limit 1
        ),
        '{}'::jsonb
      ) as current_target_meta,
      coalesce(
        (
          select to_jsonb(ut) - 'id' - 'user_id' - 'period_id' - 'created_at' - 'updated_at'
          from public.user_targets ut
          where ut.user_id = ps.promotor_id
            and ut.period_id = v_prev_period_id
          limit 1
        ),
        '{}'::jsonb
      ) as previous_target_meta,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'promotor_id', so.promotor_id,
              'transaction_date', so.transaction_date,
              'is_chip_sale', coalesce(so.is_chip_sale, false),
              'price_at_transaction', coalesce(so.price_at_transaction, 0),
              'variant_id', so.variant_id,
              'variant_label',
                trim(
                  concat_ws(
                    ' ',
                    coalesce(pr.model_name, ''),
                    coalesce(pv.ram_rom, ''),
                    coalesce(pv.color, '')
                  )
                )
            )
            order by so.transaction_date desc
          )
          from public.sales_sell_out so
          left join public.product_variants pv on pv.id = so.variant_id
          left join public.products pr on pr.id = pv.product_id
          where so.promotor_id = ps.promotor_id
            and so.deleted_at is null
            and so.transaction_date::date >= v_prev_start
            and so.transaction_date::date <= v_current_end
        ),
        '[]'::jsonb
      ) as sales_rows,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'promotor_id', va.promotor_id,
              'application_date', va.application_date,
              'outcome_status', va.outcome_status,
              'lifecycle_status', va.lifecycle_status
            )
            order by va.application_date desc
          )
          from public.vast_applications va
          where va.promotor_id = ps.promotor_id
            and va.deleted_at is null
            and va.application_date::date >= v_prev_start
            and va.application_date::date <= v_current_end
        ),
        '[]'::jsonb
      ) as vast_rows
    from promotor_scope ps
    left join public.users pu on pu.id = ps.promotor_id
    left join public.users su on su.id = ps.sator_id
    left join lateral (
      select st.store_name
      from public.assignments_promotor_store aps
      join public.stores st on st.id = aps.store_id
      where aps.promotor_id = ps.promotor_id
        and aps.active = true
      order by aps.created_at desc nulls last
      limit 1
    ) store_pick on true
  )
  select jsonb_build_object(
    'profile',
      coalesce((select to_jsonb(p) from profile p), '{}'::jsonb),
    'period',
      jsonb_build_object(
        'current_start', v_current_start,
        'current_end', v_current_end,
        'prev_start', v_prev_start,
        'prev_end', v_prev_end,
        'current_period_id', v_current_period_id,
        'prev_period_id', v_prev_period_id
      ),
    'current_spv_target_meta',
      coalesce(
        (
          select to_jsonb(ut) - 'id' - 'user_id' - 'period_id' - 'created_at' - 'updated_at'
          from public.user_targets ut
          where ut.user_id = p_spv_id
            and ut.period_id = v_current_period_id
          limit 1
        ),
        '{}'::jsonb
      ),
    'previous_spv_target_meta',
      coalesce(
        (
          select to_jsonb(ut) - 'id' - 'user_id' - 'period_id' - 'created_at' - 'updated_at'
          from public.user_targets ut
          where ut.user_id = p_spv_id
            and ut.period_id = v_prev_period_id
          limit 1
        ),
        '{}'::jsonb
      ),
    'promotors',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', pr.id,
              'name', pr.name,
              'sator_id', pr.sator_id,
              'sator_name', pr.sator_name,
              'store_name', pr.store_name,
              'current_insight', pr.current_insight,
              'previous_insight', pr.previous_insight,
              'current_target_meta', pr.current_target_meta,
              'previous_target_meta', pr.previous_target_meta,
              'sales_rows', pr.sales_rows,
              'vast_rows', pr.vast_rows
            )
            order by pr.sator_name, pr.store_name, pr.name
          )
          from promotor_rows pr
        ),
        '[]'::jsonb
      )
  )
  into v_payload;

  return coalesce(v_payload, '{}'::jsonb);
end;
$$;

grant execute on function public.get_spv_sellout_insight_snapshot(uuid, date)
to authenticated;
