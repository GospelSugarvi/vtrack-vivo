-- Phase 5: Cut over leaderboard and SATOR bonus consumers to event-based source
-- Date: 2026-03-10
-- Purpose:
-- 1. Replace legacy estimated_bonus aggregations in leaderboard/SATOR RPCs
-- 2. Preserve existing output contracts for frontend compatibility

-- =========================================================
-- 1. PROMOTOR LIVE FEED
-- =========================================================

create or replace function public.get_live_feed(
  p_user_id uuid,
  p_date date default current_date,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  feed_id uuid,
  feed_type text,
  sale_id uuid,
  promotor_id uuid,
  promotor_name text,
  store_name text,
  product_name text,
  variant_name text,
  price numeric,
  bonus numeric,
  payment_method text,
  leasing_provider text,
  customer_type text,
  notes text,
  image_url text,
  reaction_counts jsonb,
  user_reactions text[],
  comment_count integer,
  created_at timestamptz
)
language plpgsql
security definer
as $$
declare
  v_user_role text;
  v_user_area text;
begin
  select u.role, u.area into v_user_role, v_user_area
  from users u
  where u.id = p_user_id;

  return query
  with sale_bonus as (
    select
      sbe.sales_sell_out_id,
      coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus
    from public.sales_bonus_events sbe
    group by sbe.sales_sell_out_id
  )
  select
    so.id as feed_id,
    'sale'::text as feed_type,
    so.id as sale_id,
    u.id as promotor_id,
    u.full_name as promotor_name,
    st.store_name,
    (p.series || ' ' || p.model_name) as product_name,
    (pv.ram_rom || ' ' || pv.color) as variant_name,
    so.price_at_transaction as price,
    coalesce(sb.total_bonus, 0) as bonus,
    so.payment_method,
    so.leasing_provider,
    so.customer_type::text,
    so.notes,
    so.image_proof_url as image_url,
    coalesce(
      (
        select jsonb_object_agg(fr.reaction_type, fr.count)
        from (
          select fr.reaction_type, count(*)::integer as count
          from feed_reactions fr
          where fr.sale_id = so.id
          group by fr.reaction_type
        ) fr
      ),
      '{}'::jsonb
    ) as reaction_counts,
    coalesce(
      (
        select array_agg(fr.reaction_type)
        from feed_reactions fr
        where fr.sale_id = so.id and fr.user_id = p_user_id
      ),
      array[]::text[]
    ) as user_reactions,
    coalesce(
      (
        select count(*)::integer
        from feed_comments fc
        where fc.sale_id = so.id and fc.deleted_at is null
      ),
      0
    ) as comment_count,
    so.created_at
  from sales_sell_out so
  join users u on u.id = so.promotor_id
  join stores st on st.id = so.store_id
  join product_variants pv on pv.id = so.variant_id
  join products p on p.id = pv.product_id
  left join sale_bonus sb on sb.sales_sell_out_id = so.id
  where so.transaction_date = p_date
    and so.deleted_at is null
    and coalesce(so.is_chip_sale, false) = false
    and (v_user_role != 'promotor' or st.area = v_user_area)
  order by so.created_at desc
  limit p_limit
  offset p_offset;
end;
$$;

-- =========================================================
-- 2. GLOBAL LEADERBOARD FEED
-- =========================================================

create or replace function public.get_leaderboard_feed(
  p_user_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_user_role text;
  v_user_area text;
  v_result jsonb := '[]'::jsonb;
  v_area text;
  v_top_bonus jsonb;
  v_sales_by_sator record;
  v_no_sales_by_sator record;
begin
  select role, area into v_user_role, v_user_area
  from users
  where id = p_user_id;

  for v_area in
    select distinct u.area
    from users u
    where u.role in ('promotor', 'sator', 'spv')
      and (v_user_role = 'admin' or u.area = v_user_area)
      and u.area is not null
    order by u.area
  loop
    declare
      v_spv_name text;
    begin
      select full_name into v_spv_name
      from users
      where role = 'spv' and area = v_area
      limit 1;

      v_result := v_result || jsonb_build_object(
        'feed_type', 'area_header',
        'area_name', v_area,
        'spv_name', coalesce(v_spv_name, 'Tidak ada SPV')
      );
    end;

    with top_promotors as (
      select
        u.full_name,
        coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus
      from users u
      left join sales_sell_out s on s.promotor_id = u.id
        and date(s.created_at at time zone 'Asia/Makassar') = p_date
        and coalesce(s.is_chip_sale, false) = false
      left join sales_bonus_events sbe on sbe.sales_sell_out_id = s.id
      where u.area = v_area
        and u.role = 'promotor'
      group by u.id, u.full_name
      having coalesce(sum(sbe.bonus_amount), 0) > 0
      order by total_bonus desc
      limit 3
    )
    select jsonb_agg(
      jsonb_build_object(
        'name', full_name,
        'total_bonus', total_bonus
      ) order by total_bonus desc
    )
    into v_top_bonus
    from top_promotors;

    if v_top_bonus is not null and jsonb_array_length(v_top_bonus) > 0 then
      v_result := v_result || jsonb_build_object(
        'feed_type', 'top_bonus',
        'area_name', v_area,
        'top_bonus_list', v_top_bonus
      );
    end if;

    for v_sales_by_sator in
      with sator_sales as (
        select
          sator.id as sator_id,
          sator.full_name as sator_name,
          u.id as promotor_id,
          u.full_name as promotor_name,
          coalesce(u.promotor_type, 'official') as promotor_type
        from users sator
        inner join hierarchy_sator_promotor hsp on hsp.sator_id = sator.id and hsp.active = true
        inner join users u on u.id = hsp.promotor_id
        where sator.area = v_area
          and sator.role = 'sator'
          and u.role = 'promotor'
          and exists (
            select 1 from sales_sell_out s
            where s.promotor_id = u.id
              and date(s.created_at at time zone 'Asia/Makassar') = p_date
              and coalesce(s.is_chip_sale, false) = false
          )
      )
      select
        ss.sator_id,
        ss.sator_name,
        count(distinct ss.promotor_id) as promotor_count,
        (
          select count(*)
          from sales_sell_out s
          join sator_sales ss2 on ss2.promotor_id = s.promotor_id
          where ss2.sator_id = ss.sator_id
            and date(s.created_at at time zone 'Asia/Makassar') = p_date
            and coalesce(s.is_chip_sale, false) = false
        ) as total_sales,
        (
          select coalesce(sum(s.price_at_transaction), 0)
          from sales_sell_out s
          join sator_sales ss2 on ss2.promotor_id = s.promotor_id
          where ss2.sator_id = ss.sator_id
            and date(s.created_at at time zone 'Asia/Makassar') = p_date
            and coalesce(s.is_chip_sale, false) = false
        ) as total_revenue,
        (
          select coalesce(sum(sbe.bonus_amount), 0)
          from sales_sell_out s
          join sales_bonus_events sbe on sbe.sales_sell_out_id = s.id
          join sator_sales ss2 on ss2.promotor_id = s.promotor_id
          where ss2.sator_id = ss.sator_id
            and date(s.created_at at time zone 'Asia/Makassar') = p_date
            and coalesce(s.is_chip_sale, false) = false
        ) as total_bonus,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', ss.promotor_id,
            'promotor_name', ss.promotor_name,
            'promotor_type', ss.promotor_type,
            'sales', (
              select jsonb_agg(
                jsonb_build_object(
                  'product_name', p.model_name,
                  'variant_name', pv.ram_rom || ' ' || pv.color,
                  'price', s.price_at_transaction,
                  'bonus', coalesce(sbe.bonus_amount, 0)
                ) order by s.created_at desc
              )
              from sales_sell_out s
              join product_variants pv on pv.id = s.variant_id
              join products p on p.id = pv.product_id
              left join sales_bonus_events sbe on sbe.sales_sell_out_id = s.id
              where s.promotor_id = ss.promotor_id
                and date(s.created_at at time zone 'Asia/Makassar') = p_date
                and coalesce(s.is_chip_sale, false) = false
            )
          ) order by ss.promotor_name
        ) as sales_list
      from sator_sales ss
      group by ss.sator_id, ss.sator_name
      order by ss.sator_name
    loop
      v_result := v_result || jsonb_build_object(
        'feed_type', 'sales_list',
        'area_name', v_area,
        'sator_id', v_sales_by_sator.sator_id,
        'sator_name', v_sales_by_sator.sator_name,
        'promotor_count', v_sales_by_sator.promotor_count,
        'total_sales', v_sales_by_sator.total_sales,
        'total_revenue', v_sales_by_sator.total_revenue,
        'total_bonus', v_sales_by_sator.total_bonus,
        'sales_list', v_sales_by_sator.sales_list
      );
    end loop;

    for v_no_sales_by_sator in
      select
        sator.id as sator_id,
        sator.full_name as sator_name,
        jsonb_agg(
          jsonb_build_object(
            'promotor_id', u.id,
            'promotor_name', u.full_name,
            'promotor_type', coalesce(u.promotor_type, 'official')
          ) order by u.full_name
        ) as no_sales_list
      from users sator
      inner join hierarchy_sator_promotor hsp on hsp.sator_id = sator.id and hsp.active = true
      inner join users u on u.id = hsp.promotor_id
      where sator.area = v_area
        and sator.role = 'sator'
        and u.role = 'promotor'
        and not exists (
          select 1 from sales_sell_out s
          where s.promotor_id = u.id
            and date(s.created_at at time zone 'Asia/Makassar') = p_date
            and coalesce(s.is_chip_sale, false) = false
        )
      group by sator.id, sator.full_name
      having count(u.id) > 0
      order by sator.full_name
    loop
      v_result := v_result || jsonb_build_object(
        'feed_type', 'no_sales',
        'area_name', v_area,
        'sator_id', v_no_sales_by_sator.sator_id,
        'sator_name', v_no_sales_by_sator.sator_name,
        'no_sales_list', v_no_sales_by_sator.no_sales_list
      );
    end loop;
  end loop;

  return v_result;
end;
$$;

-- =========================================================
-- 3. SATOR TEAM LEADERBOARD
-- =========================================================

create or replace function public.get_team_leaderboard(
  p_sator_id uuid,
  p_period text default null
)
returns json
language plpgsql
security definer
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
    with bonus_per_sale as (
      select
        sbe.sales_sell_out_id,
        coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus
      from public.sales_bonus_events sbe
      group by sbe.sales_sell_out_id
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
      ) order by total_revenue desc
    ), '[]'::json)
    from (
      select
        row_number() over (order by coalesce(sum(s.price_at_transaction), 0) desc) as row_number,
        u.id as promotor_id,
        u.full_name,
        st.store_name,
        count(s.id) as total_units,
        coalesce(sum(s.price_at_transaction), 0) as total_revenue,
        coalesce(sum(bps.total_bonus), 0) as total_bonus
      from users u
      inner join hierarchy_sator_promotor hsp on hsp.promotor_id = u.id
        and hsp.sator_id = p_sator_id and hsp.active = true
      left join assignments_promotor_store aps on aps.promotor_id = u.id and aps.active = true
      left join stores st on st.id = aps.store_id
      left join sales_sell_out s on s.promotor_id = u.id
        and s.transaction_date >= v_start_date
        and s.transaction_date < v_end_date
        and s.deleted_at is null
        and coalesce(s.is_chip_sale, false) = false
      left join bonus_per_sale bps on bps.sales_sell_out_id = s.id
      where u.role = 'promotor'
      group by u.id, u.full_name, st.store_name
    ) sub
  );
end;
$$;

-- =========================================================
-- 4. SATOR TEAM LIVE FEED
-- =========================================================

create or replace function public.get_team_live_feed(p_sator_id uuid)
returns json
language plpgsql
security definer
as $$
begin
  return (
    with bonus_per_sale as (
      select
        sbe.sales_sell_out_id,
        coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus
      from public.sales_bonus_events sbe
      group by sbe.sales_sell_out_id
    )
    select coalesce(json_agg(
      json_build_object(
        'id', s.id,
        'type', 'sell_out',
        'promotor_id', u.id,
        'promotor_name', u.full_name,
        'store_name', st.store_name,
        'product_name', coalesce(p.model_name, 'Produk'),
        'variant_name', coalesce(pv.ram_rom, ''),
        'price', s.price_at_transaction,
        'bonus', coalesce(bps.total_bonus, 0),
        'created_at', s.created_at
      ) order by s.created_at desc
    ), '[]'::json)
    from sales_sell_out s
    inner join users u on u.id = s.promotor_id
    left join stores st on st.id = s.store_id
    left join product_variants pv on pv.id = s.variant_id
    left join products p on p.id = pv.product_id
    left join bonus_per_sale bps on bps.sales_sell_out_id = s.id
    where s.promotor_id in (
      select promotor_id from hierarchy_sator_promotor
      where sator_id = p_sator_id and active = true
    )
      and s.created_at > now() - interval '24 hours'
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
    limit 50
  );
end;
$$;

-- =========================================================
-- 5. SATOR TEAM DETAIL
-- =========================================================

create or replace function public.get_sator_tim_detail(
  p_sator_id uuid,
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_result jsonb;
begin
  with bonus_per_sale as (
    select
      sbe.sales_sell_out_id,
      coalesce(sum(sbe.bonus_amount), 0)::numeric as total_bonus
    from public.sales_bonus_events sbe
    group by sbe.sales_sell_out_id
  ),
  store_data as (
    select
      s.id as store_id,
      s.store_name,
      s.area,
      coalesce((
        select count(*)
        from sales_sell_out so
        where so.store_id = s.id
          and so.transaction_date = p_date
          and so.deleted_at is null
          and coalesce(so.is_chip_sale, false) = false
      ), 0) as total_units,
      coalesce((
        select sum(price_at_transaction)
        from sales_sell_out so
        where so.store_id = s.id
          and so.transaction_date = p_date
          and so.deleted_at is null
          and coalesce(so.is_chip_sale, false) = false
      ), 0) as total_revenue,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'promotor_id', u.id,
            'promotor_name', u.full_name,
            'promotor_type', coalesce(u.promotor_type, 'official'),
            'total_units', coalesce((
              select count(*)
              from sales_sell_out so
              join product_variants pv on pv.id = so.variant_id
              join products p on p.id = pv.product_id
              where so.promotor_id = u.id
                and so.store_id = s.id
                and so.transaction_date = p_date
                and so.deleted_at is null
                and coalesce(so.is_chip_sale, false) = false
            ), 0),
            'total_revenue', coalesce((
              select sum(so.price_at_transaction)
              from sales_sell_out so
              where so.promotor_id = u.id
                and so.store_id = s.id
                and so.transaction_date = p_date
                and so.deleted_at is null
                and coalesce(so.is_chip_sale, false) = false
            ), 0),
            'fokus_units', coalesce((
              select count(*)
              from sales_sell_out so
              join product_variants pv on pv.id = so.variant_id
              join products p on p.id = pv.product_id
              where so.promotor_id = u.id
                and so.store_id = s.id
                and so.transaction_date = p_date
                and so.deleted_at is null
                and coalesce(so.is_chip_sale, false) = false
                and p.is_focus = true
            ), 0),
            'fokus_revenue', coalesce((
              select sum(so.price_at_transaction)
              from sales_sell_out so
              join product_variants pv on pv.id = so.variant_id
              join products p on p.id = pv.product_id
              where so.promotor_id = u.id
                and so.store_id = s.id
                and so.transaction_date = p_date
                and so.deleted_at is null
                and coalesce(so.is_chip_sale, false) = false
                and p.is_focus = true
            ), 0),
            'estimated_bonus', coalesce((
              select sum(bps.total_bonus)
              from sales_sell_out so
              left join bonus_per_sale bps on bps.sales_sell_out_id = so.id
              where so.promotor_id = u.id
                and so.store_id = s.id
                and so.transaction_date = p_date
                and so.deleted_at is null
                and coalesce(so.is_chip_sale, false) = false
            ), 0)
          )
        )
        from users u
        inner join assignments_promotor_store aps
          on aps.promotor_id = u.id
          and aps.store_id = s.id
          and aps.active = true
        where u.role = 'promotor'
          and u.deleted_at is null
      ), '[]'::jsonb) as promotors
    from stores s
    inner join assignments_sator_store ass
      on ass.store_id = s.id
      and ass.sator_id = p_sator_id
      and ass.active = true
    where s.deleted_at is null
  )
  select jsonb_agg(
    jsonb_build_object(
      'store_id', store_id,
      'store_name', store_name,
      'area', area,
      'total_units', total_units,
      'total_revenue', total_revenue,
      'promotors', promotors
    )
  )
  into v_result
  from store_data;

  return coalesce(v_result, '[]'::jsonb);
end;
$$;

grant execute on function public.get_live_feed(uuid, date, integer, integer) to authenticated;
grant execute on function public.get_leaderboard_feed(uuid, date) to authenticated;
grant execute on function public.get_team_leaderboard(uuid, text) to authenticated;
grant execute on function public.get_team_live_feed(uuid) to authenticated;
grant execute on function public.get_sator_tim_detail(uuid, date) to authenticated;

