drop function if exists public.get_sell_in_finalization_summary(uuid, date, date);

create or replace function public.get_sell_in_finalization_summary(
  p_sator_id uuid,
  p_start_date date default null,
  p_end_date date default null
)
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'pending_order_count', count(*) filter (where o.status = 'pending'),
    'pending_total_items', coalesce(sum(o.total_items) filter (where o.status = 'pending'), 0),
    'pending_total_qty', coalesce(sum(o.total_qty) filter (where o.status = 'pending'), 0),
    'pending_total_value', coalesce(sum(o.total_value) filter (where o.status = 'pending'), 0),
    'finalized_order_count', count(*) filter (where o.status = 'finalized'),
    'finalized_total_items', coalesce(sum(o.total_items) filter (where o.status = 'finalized'), 0),
    'finalized_total_qty', coalesce(sum(o.total_qty) filter (where o.status = 'finalized'), 0),
    'finalized_total_value', coalesce(sum(o.total_value) filter (where o.status = 'finalized'), 0),
    'cancelled_order_count', count(*) filter (where o.status = 'cancelled'),
    'cancelled_total_items', coalesce(sum(o.total_items) filter (where o.status = 'cancelled'), 0),
    'cancelled_total_qty', coalesce(sum(o.total_qty) filter (where o.status = 'cancelled'), 0),
    'cancelled_total_value', coalesce(sum(o.total_value) filter (where o.status = 'cancelled'), 0)
  )
  from public.sell_in_orders o
  where o.sator_id = p_sator_id
    and (p_start_date is null or o.order_date >= p_start_date)
    and (p_end_date is null or o.order_date <= p_end_date);
$$;

grant execute on function public.get_sell_in_finalization_summary(uuid, date, date) to authenticated;
