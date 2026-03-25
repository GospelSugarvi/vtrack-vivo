-- Phase 3: Bonus read model and parity checks
-- Date: 2026-03-10
-- Purpose:
-- 1. Build bonus read model from sales_bonus_events
-- 2. Provide parity comparison against legacy dashboard/read paths
-- 3. Avoid breaking current bonus consumers

-- =========================================================
-- 1. BONUS SUMMARY VIEW BY USER + PERIOD
-- =========================================================

create or replace view public.v_bonus_summary_from_events as
select
  sbe.user_id,
  sbe.period_id,
  count(*) as bonus_event_count,
  coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus,
  count(*) filter (where sbe.bonus_type = 'range') as range_event_count,
  count(*) filter (where sbe.bonus_type = 'flat') as flat_event_count,
  count(*) filter (where sbe.bonus_type = 'ratio') as ratio_event_count,
  count(*) filter (where sbe.bonus_type = 'chip') as chip_event_count,
  count(*) filter (where sbe.bonus_type = 'excluded') as excluded_event_count,
  max(sbe.created_at) as last_event_at
from public.sales_bonus_events sbe
group by sbe.user_id, sbe.period_id;

comment on view public.v_bonus_summary_from_events is
  'Bonus summary derived from sales_bonus_events grouped by user and target period.';

-- =========================================================
-- 2. BONUS DETAIL VIEW FROM EVENT LEDGER
-- =========================================================

create or replace view public.v_bonus_event_details as
select
  sbe.id as bonus_event_id,
  sbe.user_id,
  sbe.period_id,
  sbe.sales_sell_out_id,
  sso.transaction_date,
  sso.serial_imei,
  sso.variant_id,
  sso.price_at_transaction,
  sso.is_chip_sale,
  sbe.bonus_type,
  sbe.bonus_amount,
  sbe.is_projection,
  sbe.calculation_version,
  sbe.rule_id,
  sbe.rule_snapshot,
  sbe.notes,
  sbe.created_at
from public.sales_bonus_events sbe
join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id;

comment on view public.v_bonus_event_details is
  'Detailed bonus events joined with sell-out transactions.';

-- =========================================================
-- 3. EVENT-BASED PROMOTOR BONUS SUMMARY FUNCTION
-- =========================================================

create or replace function public.get_promotor_bonus_summary_from_events(
  p_promotor_id uuid,
  p_start_date date default null,
  p_end_date date default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start_date date;
  v_end_date date;
  v_result json;
begin
  v_start_date := coalesce(p_start_date, date_trunc('month', current_date)::date);
  v_end_date := coalesce(
    p_end_date,
    (date_trunc('month', current_date) + interval '1 month - 1 day')::date
  );

  select json_build_object(
    'promotor_id', p_promotor_id,
    'period_start', v_start_date,
    'period_end', v_end_date,
    'event_count', count(*),
    'total_bonus', coalesce(sum(sbe.bonus_amount), 0),
    'by_bonus_type', coalesce(
      jsonb_object_agg(bonus_type_key, bonus_total) filter (where bonus_type_key is not null),
      '{}'::jsonb
    )
  )
  into v_result
  from (
    select
      sbe.bonus_type as bonus_type_key,
      sum(sbe.bonus_amount)::numeric as bonus_total
    from public.sales_bonus_events sbe
    join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id
    where sbe.user_id = p_promotor_id
      and sso.transaction_date between v_start_date and v_end_date
    group by sbe.bonus_type
  ) t
  right join public.sales_bonus_events sbe
    on false
  where false;

  if v_result is null then
    select json_build_object(
      'promotor_id', p_promotor_id,
      'period_start', v_start_date,
      'period_end', v_end_date,
      'event_count', (
        select count(*)
        from public.sales_bonus_events sbe
        join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id
        where sbe.user_id = p_promotor_id
          and sso.transaction_date between v_start_date and v_end_date
      ),
      'total_bonus', (
        select coalesce(sum(sbe.bonus_amount), 0)
        from public.sales_bonus_events sbe
        join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id
        where sbe.user_id = p_promotor_id
          and sso.transaction_date between v_start_date and v_end_date
      ),
      'by_bonus_type', (
        select coalesce(
          jsonb_object_agg(x.bonus_type, x.total_bonus),
          '{}'::jsonb
        )
        from (
          select sbe.bonus_type, sum(sbe.bonus_amount)::numeric as total_bonus
          from public.sales_bonus_events sbe
          join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id
          where sbe.user_id = p_promotor_id
            and sso.transaction_date between v_start_date and v_end_date
          group by sbe.bonus_type
        ) x
      )
    ) into v_result;
  end if;

  return v_result;
end;
$$;

grant execute on function public.get_promotor_bonus_summary_from_events(uuid, date, date) to authenticated;

comment on function public.get_promotor_bonus_summary_from_events is
  'Get promotor bonus summary using sales_bonus_events as source.';

-- =========================================================
-- 4. EVENT-BASED PROMOTOR BONUS DETAIL FUNCTION
-- =========================================================

create or replace function public.get_promotor_bonus_details_from_events(
  p_promotor_id uuid,
  p_start_date date default null,
  p_end_date date default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  bonus_event_id uuid,
  sales_sell_out_id uuid,
  transaction_date date,
  serial_imei text,
  price_at_transaction numeric,
  bonus_type text,
  bonus_amount numeric,
  is_projection boolean,
  calculation_version text,
  notes text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start_date date;
  v_end_date date;
begin
  v_start_date := coalesce(p_start_date, date_trunc('month', current_date)::date);
  v_end_date := coalesce(
    p_end_date,
    (date_trunc('month', current_date) + interval '1 month - 1 day')::date
  );

  return query
  select
    sbe.id,
    sbe.sales_sell_out_id,
    sso.transaction_date,
    sso.serial_imei,
    sso.price_at_transaction,
    sbe.bonus_type,
    sbe.bonus_amount,
    sbe.is_projection,
    sbe.calculation_version,
    sbe.notes
  from public.sales_bonus_events sbe
  join public.sales_sell_out sso on sso.id = sbe.sales_sell_out_id
  where sbe.user_id = p_promotor_id
    and sso.transaction_date between v_start_date and v_end_date
  order by sso.transaction_date desc, sbe.created_at desc
  limit p_limit
  offset p_offset;
end;
$$;

grant execute on function public.get_promotor_bonus_details_from_events(uuid, date, date, integer, integer) to authenticated;

comment on function public.get_promotor_bonus_details_from_events is
  'Get detailed promotor bonus events from sales_bonus_events.';

-- =========================================================
-- 5. PARITY VIEW: LEDGER VS LEGACY DASHBOARD
-- =========================================================

create or replace view public.v_bonus_parity_dashboard_vs_events as
with event_totals as (
  select
    sbe.user_id,
    sbe.period_id,
    coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus_events
  from public.sales_bonus_events sbe
  group by sbe.user_id, sbe.period_id
)
select
  dpm.user_id,
  dpm.period_id,
  coalesce(dpm.estimated_bonus_total, 0)::numeric as total_bonus_dashboard,
  coalesce(et.total_bonus_events, 0)::numeric as total_bonus_events,
  coalesce(et.total_bonus_events, 0)::numeric - coalesce(dpm.estimated_bonus_total, 0)::numeric as bonus_gap,
  case
    when coalesce(dpm.estimated_bonus_total, 0)::numeric = coalesce(et.total_bonus_events, 0)::numeric
      then 'MATCH'
    else 'MISMATCH'
  end as parity_status
from public.dashboard_performance_metrics dpm
left join event_totals et
  on et.user_id = dpm.user_id
 and et.period_id = dpm.period_id;

comment on view public.v_bonus_parity_dashboard_vs_events is
  'Compare legacy dashboard estimated bonus totals against sales_bonus_events totals.';

-- =========================================================
-- 6. PARITY QUERY HELPER FUNCTION
-- =========================================================

create or replace function public.get_bonus_parity_summary()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'total_rows', count(*),
    'matched_rows', count(*) filter (where parity_status = 'MATCH'),
    'mismatched_rows', count(*) filter (where parity_status = 'MISMATCH'),
    'total_dashboard_bonus', coalesce(sum(total_bonus_dashboard), 0),
    'total_event_bonus', coalesce(sum(total_bonus_events), 0),
    'total_gap', coalesce(sum(bonus_gap), 0)
  )
  from public.v_bonus_parity_dashboard_vs_events;
$$;

grant execute on function public.get_bonus_parity_summary() to authenticated;

