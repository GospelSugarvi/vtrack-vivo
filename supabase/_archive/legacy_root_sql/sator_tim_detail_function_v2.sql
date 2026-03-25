-- Function to get Sator's team detail (stores and promotors)
-- V2: Filter by stores assigned to sator (assignments_sator_store)

create or replace function get_sator_tim_detail(
  p_sator_id uuid,
  p_date date
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_result jsonb;
begin
  -- Get stores assigned to this sator with promotor details
  select jsonb_agg(
    jsonb_build_object(
      'store_id', s.id,
      'store_name', s.store_name,
      'total_units', coalesce(store_totals.total_units, 0),
      'total_revenue', coalesce(store_totals.total_revenue, 0),
      'promotors', coalesce(promotor_details, '[]'::jsonb)
    )
  )
  into v_result
  from stores s
  -- IMPORTANT: Filter by stores assigned to this sator
  inner join assignments_sator_store ass on ass.store_id = s.id 
    and ass.sator_id = p_sator_id and ass.active = true
  -- Get store totals
  left join lateral (
    select 
      count(*) as total_units,
      sum(price_at_transaction) as total_revenue
    from sales_sell_out so
    where so.store_id = s.id
      and so.transaction_date = p_date
      and so.deleted_at is null
  ) store_totals on true
  -- Get promotor details for this store
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'promotor_id', u.id,
        'promotor_name', u.full_name,
        'promotor_type', coalesce(u.promotor_type, 'official'),
        'total_units', coalesce(prom_stats.total_units, 0),
        'total_revenue', coalesce(prom_stats.total_revenue, 0),
        'fokus_units', coalesce(prom_stats.fokus_units, 0),
        'fokus_revenue', coalesce(prom_stats.fokus_revenue, 0),
        'estimated_bonus', coalesce(prom_stats.estimated_bonus, 0)
      )
    ) as promotor_details
    from users u
    inner join assignments_promotor_store aps on aps.promotor_id = u.id 
      and aps.store_id = s.id and aps.active = true
    -- Get promotor statistics
    left join lateral (
      select 
        count(*) as total_units,
        sum(so.price_at_transaction) as total_revenue,
        sum(case when p.is_focus then 1 else 0 end) as fokus_units,
        sum(case when p.is_focus then so.price_at_transaction else 0 end) as fokus_revenue,
        sum(so.estimated_bonus) as estimated_bonus
      from sales_sell_out so
      inner join product_variants pv on pv.id = so.variant_id
      inner join products p on p.id = pv.product_id
      where so.promotor_id = u.id
        and so.store_id = s.id
        and so.transaction_date = p_date
        and so.deleted_at is null
    ) prom_stats on true
    where u.role = 'promotor' and u.deleted_at is null
  ) promotor_details on true
  where s.deleted_at is null
  group by s.id, s.store_name, store_totals.total_units, store_totals.total_revenue, promotor_details;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

-- Grant execute permission
grant execute on function get_sator_tim_detail(uuid, date) to authenticated;
