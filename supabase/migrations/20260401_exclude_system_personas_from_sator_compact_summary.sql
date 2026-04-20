create or replace function public.get_sator_compact_summary(
  p_date date default current_date
)
returns table (
  sator_id uuid,
  sator_name text,
  sellout_target numeric,
  sellout_actual numeric,
  sellout_pct numeric,
  focus_target numeric,
  focus_actual numeric,
  focus_pct numeric
)
language sql
security definer
set search_path = public
as $$
  with promotor_sator as (
    select
      u.id as promotor_id,
      chosen.sator_id,
      coalesce(s.full_name, 'Tanpa SATOR') as sator_name
    from public.users u
    left join lateral (
      select hsp.sator_id
      from public.hierarchy_sator_promotor hsp
      join public.users su
        on su.id = hsp.sator_id
       and su.role = 'sator'
      where hsp.promotor_id = u.id
        and hsp.active = true
      order by hsp.created_at desc, hsp.sator_id
      limit 1
    ) chosen on true
    left join public.users s on s.id = chosen.sator_id
    where u.role = 'promotor'
      and u.deleted_at is null
      and not exists (
        select 1
        from public.system_personas sp
        where sp.linked_user_id = u.id
          and sp.is_active = true
      )
  ),
  promotor_daily as (
    select
      ps.sator_id,
      ps.sator_name,
      ps.promotor_id,
      coalesce(d.target_daily_all_type, 0)::numeric as sellout_target,
      coalesce(d.actual_daily_all_type, 0)::numeric as sellout_actual,
      coalesce(d.target_daily_focus, 0)::numeric as focus_target,
      coalesce(d.actual_daily_focus, 0)::numeric as focus_actual
    from promotor_sator ps
    left join lateral public.get_daily_target_dashboard(ps.promotor_id, p_date) d
      on true
  )
  select
    pd.sator_id,
    pd.sator_name,
    coalesce(sum(pd.sellout_target), 0)::numeric as sellout_target,
    coalesce(sum(pd.sellout_actual), 0)::numeric as sellout_actual,
    case
      when coalesce(sum(pd.sellout_target), 0) > 0
        then round((coalesce(sum(pd.sellout_actual), 0) / sum(pd.sellout_target)) * 100, 1)
      else 0
    end::numeric as sellout_pct,
    coalesce(sum(pd.focus_target), 0)::numeric as focus_target,
    coalesce(sum(pd.focus_actual), 0)::numeric as focus_actual,
    case
      when coalesce(sum(pd.focus_target), 0) > 0
        then round((coalesce(sum(pd.focus_actual), 0) / sum(pd.focus_target)) * 100, 1)
      else 0
    end::numeric as focus_pct
  from promotor_daily pd
  group by pd.sator_id, pd.sator_name
  order by pd.sator_name;
$$;
