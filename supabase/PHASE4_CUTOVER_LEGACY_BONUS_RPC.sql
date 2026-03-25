-- Phase 4: Cut over legacy bonus RPCs to event-based source
-- Date: 2026-03-10

create or replace function public.get_promotor_bonus_summary(
  p_promotor_id uuid,
  p_start_date date default null,
  p_end_date date default null
)
returns json
language sql
security definer
set search_path = public
as $$
  select public.get_promotor_bonus_summary_from_events(
    p_promotor_id,
    p_start_date,
    p_end_date
  );
$$;

comment on function public.get_promotor_bonus_summary is
  'Compatibility wrapper that now reads from sales_bonus_events-based summary.';

create or replace function public.get_promotor_bonus_details(
  p_promotor_id uuid,
  p_start_date date default null,
  p_end_date date default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  transaction_id uuid,
  transaction_date date,
  product_name text,
  variant_name text,
  price numeric,
  bonus_amount numeric,
  payment_method text,
  leasing_provider text
)
language sql
security definer
set search_path = public
as $$
  select
    sso.id as transaction_id,
    sso.transaction_date,
    (p.series || ' ' || p.model_name)::text as product_name,
    trim(concat(coalesce(pv.ram_rom, ''), ' ', coalesce(pv.color, '')))::text as variant_name,
    sso.price_at_transaction as price,
    d.bonus_amount,
    sso.payment_method,
    sso.leasing_provider
  from public.get_promotor_bonus_details_from_events(
    p_promotor_id,
    p_start_date,
    p_end_date,
    p_limit,
    p_offset
  ) d
  join public.sales_sell_out sso on sso.id = d.sales_sell_out_id
  join public.product_variants pv on pv.id = sso.variant_id
  join public.products p on p.id = pv.product_id
  order by sso.transaction_date desc, d.bonus_event_id desc;
$$;

comment on function public.get_promotor_bonus_details is
  'Compatibility wrapper that now reads detailed bonus from sales_bonus_events.';

grant execute on function public.get_promotor_bonus_summary(uuid, date, date) to authenticated;
grant execute on function public.get_promotor_bonus_details(uuid, date, date, integer, integer) to authenticated;

