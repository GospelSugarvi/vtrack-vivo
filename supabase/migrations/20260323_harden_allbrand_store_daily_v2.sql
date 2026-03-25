create unique index if not exists uq_allbrand_reports_store_daily
on public.allbrand_reports(store_id, report_date);

create or replace function public.normalize_allbrand_report_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.brand_data_daily := public.safe_allbrand_object(new.brand_data_daily);
  new.brand_data := public.safe_allbrand_object(new.brand_data);
  new.leasing_sales_daily := public.safe_allbrand_object(new.leasing_sales_daily);
  new.leasing_sales := public.safe_allbrand_object(new.leasing_sales);
  new.vivo_auto_data := public.safe_allbrand_object(new.vivo_auto_data);
  new.vivo_promotor_count := greatest(coalesce(new.vivo_promotor_count, 0), 0);
  new.notes := nullif(btrim(coalesce(new.notes, '')), '');
  new.status := coalesce(nullif(btrim(coalesce(new.status, '')), ''), 'submitted');

  new.daily_total_units := coalesce((
    select sum(
      coalesce((b.value->>'under_2m')::int, 0) +
      coalesce((b.value->>'2m_4m')::int, 0) +
      coalesce((b.value->>'4m_6m')::int, 0) +
      coalesce((b.value->>'above_6m')::int, 0)
    )
    from jsonb_each(new.brand_data_daily) b
  ), 0);

  return new;
end;
$$;

drop trigger if exists trg_normalize_allbrand_report_row on public.allbrand_reports;

create trigger trg_normalize_allbrand_report_row
before insert or update of brand_data_daily, brand_data, leasing_sales_daily, leasing_sales, vivo_auto_data, vivo_promotor_count, notes, status
on public.allbrand_reports
for each row
execute function public.normalize_allbrand_report_row();

create or replace function public.recompute_allbrand_store(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_store_id is null then
    return;
  end if;

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
  where r.id = c.id
    and (
      r.brand_data is distinct from c.cumulative_brand
      or r.leasing_sales is distinct from c.cumulative_leasing
      or r.daily_total_units is distinct from c.daily_total
      or r.cumulative_total_units is distinct from c.cumulative_total
    );
end;
$$;

create or replace function public.trigger_recompute_allbrand_store()
returns trigger
language plpgsql
security definer
set search_path = public
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

create or replace function public.upsert_allbrand_report_store_daily(
  p_existing_id uuid,
  p_promotor_id uuid,
  p_store_id uuid,
  p_report_date date,
  p_brand_data_daily jsonb,
  p_leasing_sales_daily jsonb,
  p_vivo_auto_data jsonb,
  p_vivo_promotor_count integer,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report_id uuid;
begin
  if p_promotor_id is null then
    raise exception 'promotor_id wajib diisi' using errcode = '22023';
  end if;
  if p_store_id is null then
    raise exception 'store_id wajib diisi' using errcode = '22023';
  end if;
  if p_report_date is null then
    raise exception 'report_date wajib diisi' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('allbrand:' || p_store_id::text, 0));

  insert into public.allbrand_reports (
    id,
    promotor_id,
    store_id,
    report_date,
    brand_data_daily,
    leasing_sales_daily,
    vivo_auto_data,
    vivo_promotor_count,
    notes,
    status
  )
  values (
    coalesce(p_existing_id, gen_random_uuid()),
    p_promotor_id,
    p_store_id,
    p_report_date,
    public.safe_allbrand_object(p_brand_data_daily),
    public.safe_allbrand_object(p_leasing_sales_daily),
    public.safe_allbrand_object(p_vivo_auto_data),
    greatest(coalesce(p_vivo_promotor_count, 0), 0),
    nullif(btrim(coalesce(p_notes, '')), ''),
    'submitted'
  )
  on conflict (store_id, report_date) do update
  set
    brand_data_daily = excluded.brand_data_daily,
    leasing_sales_daily = excluded.leasing_sales_daily,
    vivo_auto_data = excluded.vivo_auto_data,
    vivo_promotor_count = excluded.vivo_promotor_count,
    notes = excluded.notes,
    updated_at = now()
  returning id into v_report_id;

  perform public.recompute_allbrand_store(p_store_id);

  return v_report_id;
end;
$$;

grant execute on function public.recompute_allbrand_store(uuid) to authenticated;
grant execute on function public.upsert_allbrand_report_store_daily(uuid, uuid, uuid, date, jsonb, jsonb, jsonb, integer, text) to authenticated;

select public.recompute_allbrand_store(store_id)
from (
  select distinct store_id
  from public.allbrand_reports
  where store_id is not null
) stores;
