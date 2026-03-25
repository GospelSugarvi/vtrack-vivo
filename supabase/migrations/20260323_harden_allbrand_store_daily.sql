create unique index if not exists uq_allbrand_reports_store_daily
on public.allbrand_reports(store_id, report_date);

create or replace function public.recompute_allbrand_store(p_store_id uuid)
returns void
language plpgsql
as $$
begin
  if p_store_id is null then
    return;
  end if;

  update public.allbrand_reports
  set
    brand_data_daily = public.safe_allbrand_object(brand_data_daily),
    brand_data = public.safe_allbrand_object(brand_data),
    leasing_sales_daily = public.safe_allbrand_object(leasing_sales_daily),
    leasing_sales = public.safe_allbrand_object(leasing_sales)
  where store_id = p_store_id;

  with recursive ordered as (
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
    where r.store_id = p_store_id
  ),
  cumulative as (
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
end;
$$;

create or replace function public.trigger_recompute_allbrand_store()
returns trigger
language plpgsql
as $$
begin
  perform public.recompute_allbrand_store(coalesce(new.store_id, old.store_id));
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_recompute_allbrand_store on public.allbrand_reports;

create trigger trg_recompute_allbrand_store
after insert or update of brand_data_daily, leasing_sales_daily, report_date, store_id or delete
on public.allbrand_reports
for each row
execute function public.trigger_recompute_allbrand_store();

select public.recompute_allbrand_store(store_id)
from (
  select distinct store_id
  from public.allbrand_reports
  where store_id is not null
) stores;
