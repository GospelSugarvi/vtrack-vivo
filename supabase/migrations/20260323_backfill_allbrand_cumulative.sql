create or replace function public.safe_allbrand_object(p_value jsonb)
returns jsonb
language plpgsql
immutable
as $$
begin
  if p_value is null then
    return '{}'::jsonb;
  end if;

  if jsonb_typeof(p_value) = 'object' then
    return p_value;
  end if;

  if jsonb_typeof(p_value) = 'string' then
    begin
      return trim(both '"' from p_value::text)::jsonb;
    exception when others then
      return '{}'::jsonb;
    end;
  end if;

  return '{}'::jsonb;
end;
$$;

create or replace function public.merge_allbrand_brand_totals(
  prev_data jsonb,
  daily_data jsonb
)
returns jsonb
language sql
immutable
as $$
  with prev_rows as (
    select key, value
    from jsonb_each(public.safe_allbrand_object(prev_data))
  ),
  daily_rows as (
    select key, value
    from jsonb_each(public.safe_allbrand_object(daily_data))
  ),
  keys as (
    select key from prev_rows
    union
    select key from daily_rows
  )
  select coalesce(
    jsonb_object_agg(
      k.key,
      jsonb_build_object(
        'under_2m', coalesce((p.value->>'under_2m')::int, 0) + coalesce((d.value->>'under_2m')::int, 0),
        '2m_4m', coalesce((p.value->>'2m_4m')::int, 0) + coalesce((d.value->>'2m_4m')::int, 0),
        '4m_6m', coalesce((p.value->>'4m_6m')::int, 0) + coalesce((d.value->>'4m_6m')::int, 0),
        'above_6m', coalesce((p.value->>'above_6m')::int, 0) + coalesce((d.value->>'above_6m')::int, 0),
        'promotor_count', case
          when coalesce((d.value->>'promotor_count')::int, 0) > 0
            then coalesce((d.value->>'promotor_count')::int, 0)
          else coalesce((p.value->>'promotor_count')::int, 0)
        end
      )
    ),
    '{}'::jsonb
  )
  from keys k
  left join prev_rows p on p.key = k.key
  left join daily_rows d on d.key = k.key;
$$;

create or replace function public.merge_allbrand_count_totals(
  prev_data jsonb,
  daily_data jsonb
)
returns jsonb
language sql
immutable
as $$
  with prev_rows as (
    select key, value
    from jsonb_each(public.safe_allbrand_object(prev_data))
  ),
  daily_rows as (
    select key, value
    from jsonb_each(public.safe_allbrand_object(daily_data))
  ),
  keys as (
    select key from prev_rows
    union
    select key from daily_rows
  )
  select coalesce(
    jsonb_object_agg(
      k.key,
      to_jsonb(coalesce((p.value)::int, 0) + coalesce((d.value)::int, 0))
    ),
    '{}'::jsonb
  )
  from keys k
  left join prev_rows p on p.key = k.key
  left join daily_rows d on d.key = k.key;
$$;

with normalized as (
  select
    id,
    public.safe_allbrand_object(brand_data_daily) as brand_data_daily,
    public.safe_allbrand_object(brand_data) as brand_data,
    public.safe_allbrand_object(leasing_sales_daily) as leasing_sales_daily,
    public.safe_allbrand_object(leasing_sales) as leasing_sales
  from public.allbrand_reports
),
updated_json as (
  update public.allbrand_reports r
  set
    brand_data_daily = n.brand_data_daily,
    brand_data = n.brand_data,
    leasing_sales_daily = n.leasing_sales_daily,
    leasing_sales = n.leasing_sales
  from normalized n
  where r.id = n.id
  returning r.id
),
ordered as (
  select
    r.id,
    r.store_id,
    r.report_date,
    r.created_at,
    public.safe_allbrand_object(r.brand_data_daily) as brand_daily,
    public.safe_allbrand_object(r.leasing_sales_daily) as leasing_daily,
    coalesce((
      select sum(
        coalesce((b.value->>'under_2m')::int, 0) +
        coalesce((b.value->>'2m_4m')::int, 0) +
        coalesce((b.value->>'4m_6m')::int, 0) +
        coalesce((b.value->>'above_6m')::int, 0)
      )
      from jsonb_each(public.safe_allbrand_object(r.brand_data_daily)) b
    ), 0) as daily_total,
    row_number() over (
      partition by r.store_id
      order by r.report_date asc, r.created_at asc, r.id asc
    ) as rn
  from public.allbrand_reports r
),
recursive cumulative as (
  select
    o.id,
    o.store_id,
    o.rn,
    o.brand_daily as cumulative_brand,
    o.leasing_daily as cumulative_leasing,
    o.daily_total,
    o.daily_total as cumulative_total
  from ordered o
  where o.rn = 1

  union all

  select
    o.id,
    o.store_id,
    o.rn,
    public.merge_allbrand_brand_totals(c.cumulative_brand, o.brand_daily),
    public.merge_allbrand_count_totals(c.cumulative_leasing, o.leasing_daily),
    o.daily_total,
    c.cumulative_total + o.daily_total
  from cumulative c
  join ordered o
    on o.store_id = c.store_id
   and o.rn = c.rn + 1
)
update public.allbrand_reports r
set
  brand_data = c.cumulative_brand,
  leasing_sales = c.cumulative_leasing,
  daily_total_units = c.daily_total,
  cumulative_total_units = c.cumulative_total
from cumulative c
where r.id = c.id;
