create or replace function public.get_team_leaderboard(
  p_sator_id uuid,
  p_period text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period text;
  v_start_date date;
  v_end_date date;
begin
  v_period := coalesce(p_period, to_char(current_date, 'YYYY-MM'));
  v_start_date := (v_period || '-01')::date;
  v_end_date := (v_start_date + interval '1 month')::date;

  return (
    with sales_scope as (
      select
        s.id,
        s.promotor_id,
        s.price_at_transaction,
        public.resolve_effective_bonus_amount(s.id, s.estimated_bonus) as effective_bonus
      from public.sales_sell_out s
      where s.transaction_date >= v_start_date
        and s.transaction_date < v_end_date
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false
    )
    select coalesce(json_agg(
      json_build_object(
        'rank', row_number,
        'promotor_id', promotor_id,
        'promotor_name', full_name,
        'store_name', store_name,
        'total_units', total_units,
        'total_revenue', total_revenue,
        'total_bonus', total_bonus
      ) order by total_revenue desc, full_name
    ), '[]'::json)
    from (
      select
        row_number() over (
          order by coalesce(sum(ss.price_at_transaction), 0) desc, u.full_name
        ) as row_number,
        u.id as promotor_id,
        u.full_name,
        st.store_name,
        count(ss.id) as total_units,
        coalesce(sum(ss.price_at_transaction), 0) as total_revenue,
        coalesce(sum(ss.effective_bonus), 0) as total_bonus
      from public.users u
      inner join public.hierarchy_sator_promotor hsp
        on hsp.promotor_id = u.id
       and hsp.sator_id = p_sator_id
       and hsp.active = true
      left join public.assignments_promotor_store aps
        on aps.promotor_id = u.id
       and aps.active = true
      left join public.stores st on st.id = aps.store_id
      left join sales_scope ss on ss.promotor_id = u.id
      where u.role = 'promotor'
      group by u.id, u.full_name, st.store_name
    ) sub
  );
end;
$$;

create or replace function public.get_sator_leaderboard(
  p_sator_id uuid,
  p_period text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period text;
  v_start_date date;
  v_end_date date;
  v_period_id uuid;
begin
  v_period := coalesce(p_period, to_char(current_date, 'YYYY-MM'));
  v_start_date := (v_period || '-01')::date;
  v_end_date := (v_start_date + interval '1 month')::date;

  select tp.id
  into v_period_id
  from public.target_periods tp
  where tp.start_date <= v_start_date
    and tp.end_date >= (v_end_date - interval '1 day')::date
    and tp.deleted_at is null
  order by tp.start_date desc
  limit 1;

  return (
    with sales_scope as (
      select
        so.id,
        so.promotor_id,
        so.price_at_transaction,
        public.resolve_effective_bonus_amount(so.id, so.estimated_bonus) as effective_bonus
      from public.sales_sell_out so
      where so.transaction_date >= v_start_date
        and so.transaction_date < v_end_date
        and so.deleted_at is null
        and coalesce(so.is_chip_sale, false) = false
    ),
    user_target as (
      select distinct on (ut.user_id)
        ut.user_id,
        coalesce(ut.target_sell_out, 0)::numeric as target_revenue
      from public.user_targets ut
      where v_period_id is not null
        and ut.period_id = v_period_id
      order by ut.user_id, ut.updated_at desc
    )
    select coalesce(json_agg(row_to_json(t) order by t.total_revenue desc, t.promotor_name), '[]'::json)
    from (
      select
        u.id as promotor_id,
        u.full_name as promotor_name,
        s.store_name,
        count(ss.id) as total_units,
        coalesce(sum(ss.price_at_transaction), 0) as total_revenue,
        coalesce(sum(ss.effective_bonus), 0) as total_bonus,
        coalesce(
          case
            when coalesce(ut.target_revenue, 0) > 0 then
              round(coalesce(sum(ss.price_at_transaction), 0) / ut.target_revenue * 100, 1)
            else 0
          end,
          0
        ) as achievement_percent
      from public.hierarchy_sator_promotor hsp
      inner join public.users u on hsp.promotor_id = u.id
      left join public.assignments_promotor_store aps
        on u.id = aps.promotor_id
       and aps.active = true
      left join public.stores s on aps.store_id = s.id
      left join sales_scope ss on u.id = ss.promotor_id
      left join user_target ut on ut.user_id = u.id
      where hsp.sator_id = p_sator_id
        and hsp.active = true
      group by u.id, u.full_name, s.store_name, ut.target_revenue
    ) t
  );
end;
$$;
