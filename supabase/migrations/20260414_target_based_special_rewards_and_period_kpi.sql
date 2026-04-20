-- Align special reward logic to user targets and support KPI settings per period.

create table if not exists public.special_reward_configs (
  id uuid primary key default extensions.uuid_generate_v4(),
  period_id uuid not null references public.target_periods(id) on delete cascade,
  role text not null check (role in ('sator', 'spv')),
  special_bundle_id uuid not null references public.special_focus_bundles(id) on delete cascade,
  reward_amount integer not null default 0,
  penalty_threshold integer not null default 80,
  penalty_amount integer not null default 0,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_id, role, special_bundle_id)
);

create index if not exists idx_special_reward_configs_period_role
  on public.special_reward_configs(period_id, role);

alter table if exists public.special_reward_configs enable row level security;

drop policy if exists "special_reward_configs_read_authenticated" on public.special_reward_configs;
create policy "special_reward_configs_read_authenticated"
on public.special_reward_configs
for select
to authenticated
using (true);

drop policy if exists "special_reward_configs_manage_admin" on public.special_reward_configs;
create policy "special_reward_configs_manage_admin"
on public.special_reward_configs
for all
to authenticated
using (public.is_admin_simple())
with check (public.is_admin_simple());

create or replace function public.update_special_reward_configs_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists special_reward_configs_updated_at on public.special_reward_configs;
create trigger special_reward_configs_updated_at
before update on public.special_reward_configs
for each row
execute function public.update_special_reward_configs_updated_at();

insert into public.special_reward_configs (
  period_id,
  role,
  special_bundle_id,
  reward_amount,
  penalty_threshold,
  penalty_amount,
  description
)
select
  sb.period_id,
  sr.role,
  sr.special_bundle_id,
  max(coalesce(sr.reward_amount, 0)) as reward_amount,
  max(coalesce(sr.penalty_threshold, 80)) as penalty_threshold,
  max(coalesce(sr.penalty_amount, 0)) as penalty_amount,
  max(nullif(trim(coalesce(sr.product_name, '')), '')) as description
from public.special_rewards sr
join public.special_focus_bundles sb on sb.id = sr.special_bundle_id
where sr.special_bundle_id is not null
group by sb.period_id, sr.role, sr.special_bundle_id
on conflict (period_id, role, special_bundle_id) do update
set
  reward_amount = excluded.reward_amount,
  penalty_threshold = excluded.penalty_threshold,
  penalty_amount = excluded.penalty_amount,
  description = coalesce(excluded.description, public.special_reward_configs.description),
  updated_at = now();

create table if not exists public.kpi_metric_templates (
  id uuid primary key default extensions.uuid_generate_v4(),
  role text not null check (role in ('sator', 'spv')),
  metric_code text not null,
  display_name text not null,
  description text,
  score_source text not null default 'achievement'
    check (score_source in ('achievement', 'range', 'manual')),
  score_config jsonb not null default '{}'::jsonb,
  default_weight integer not null default 0,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (role, metric_code)
);

create index if not exists idx_kpi_metric_templates_role
  on public.kpi_metric_templates(role, sort_order, display_name);

alter table if exists public.kpi_metric_templates enable row level security;

drop policy if exists "kpi_metric_templates_read_authenticated" on public.kpi_metric_templates;
create policy "kpi_metric_templates_read_authenticated"
on public.kpi_metric_templates
for select
to authenticated
using (true);

drop policy if exists "kpi_metric_templates_manage_admin" on public.kpi_metric_templates;
create policy "kpi_metric_templates_manage_admin"
on public.kpi_metric_templates
for all
to authenticated
using (public.is_admin_simple())
with check (public.is_admin_simple());

create table if not exists public.kpi_period_settings (
  id uuid primary key default extensions.uuid_generate_v4(),
  period_id uuid not null references public.target_periods(id) on delete cascade,
  role text not null check (role in ('sator', 'spv')),
  template_id uuid references public.kpi_metric_templates(id) on delete set null,
  metric_code text not null,
  display_name text not null,
  description text,
  score_source text not null default 'achievement'
    check (score_source in ('achievement', 'range', 'manual')),
  score_config jsonb not null default '{}'::jsonb,
  weight integer not null default 0,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (period_id, role, metric_code)
);

create index if not exists idx_kpi_period_settings_period_role
  on public.kpi_period_settings(period_id, role, sort_order, display_name);

alter table if exists public.kpi_period_settings enable row level security;

drop policy if exists "kpi_period_settings_read_authenticated" on public.kpi_period_settings;
create policy "kpi_period_settings_read_authenticated"
on public.kpi_period_settings
for select
to authenticated
using (true);

drop policy if exists "kpi_period_settings_manage_admin" on public.kpi_period_settings;
create policy "kpi_period_settings_manage_admin"
on public.kpi_period_settings
for all
to authenticated
using (public.is_admin_simple())
with check (public.is_admin_simple());

create or replace function public.update_kpi_metric_templates_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists kpi_metric_templates_updated_at on public.kpi_metric_templates;
create trigger kpi_metric_templates_updated_at
before update on public.kpi_metric_templates
for each row
execute function public.update_kpi_metric_templates_updated_at();

create or replace function public.update_kpi_period_settings_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists kpi_period_settings_updated_at on public.kpi_period_settings;
create trigger kpi_period_settings_updated_at
before update on public.kpi_period_settings
for each row
execute function public.update_kpi_period_settings_updated_at();

create or replace function public.get_kpi_metric_code(p_name text)
returns text
language plpgsql
immutable
as $$
declare
  v_name text := lower(coalesce(p_name, ''));
begin
  if v_name like '%sell out all%' then
    return 'sell_out_all';
  elsif v_name like '%sell out produk fokus%' or v_name like '%sell out fokus%' then
    return 'sell_out_focus';
  elsif v_name like '%sell in%' then
    return 'sell_in_all';
  elsif v_name like '%low sellout%' or v_name like '%low sell%' then
    return 'low_sellout';
  elsif v_name like '%kpi ma%' or v_name like '%ma%' then
    return 'kpi_ma';
  end if;
  return regexp_replace(trim(coalesce(p_name, 'metric')), '[^a-zA-Z0-9]+', '_', 'g');
end;
$$;

create or replace function public.get_default_low_sellout_score_config()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'ranges',
    jsonb_build_array(
      jsonb_build_object('max_pct', 10, 'score', 100),
      jsonb_build_object('min_pct', 11, 'max_pct', 20, 'score', 80),
      jsonb_build_object('min_pct', 21, 'max_pct', 30, 'score', 60),
      jsonb_build_object('min_pct', 30.0001, 'score', 40)
    )
  );
$$;

insert into public.kpi_metric_templates (
  role,
  metric_code,
  display_name,
  description,
  score_source,
  score_config,
  default_weight,
  sort_order,
  is_active
)
select
  ks.role,
  public.get_kpi_metric_code(ks.kpi_name),
  ks.kpi_name,
  ks.description,
  case
    when public.get_kpi_metric_code(ks.kpi_name) = 'kpi_ma' then 'manual'
    else 'achievement'
  end,
  case
    when public.get_kpi_metric_code(ks.kpi_name) = 'low_sellout'
      then public.get_default_low_sellout_score_config()
    else '{}'::jsonb
  end,
  coalesce(ks.weight, 0),
  row_number() over (partition by ks.role order by ks.weight desc, ks.kpi_name),
  true
from public.kpi_settings ks
where public.get_kpi_metric_code(ks.kpi_name) <> ''
on conflict (role, metric_code) do update
set
  display_name = excluded.display_name,
  description = excluded.description,
  score_source = excluded.score_source,
  score_config = case
    when public.kpi_metric_templates.metric_code = 'low_sellout'
      then public.get_default_low_sellout_score_config()
    else excluded.score_config
  end,
  default_weight = excluded.default_weight,
  updated_at = now();

insert into public.kpi_metric_templates (
  role,
  metric_code,
  display_name,
  description,
  score_source,
  score_config,
  default_weight,
  sort_order,
  is_active
)
values
  ('sator', 'low_sellout', 'Low Sellout', 'Persentase promotor low sellout dalam tim sator.', 'range', public.get_default_low_sellout_score_config(), 10, 90, true),
  ('spv', 'low_sellout', 'Low Sellout', 'Persentase promotor low sellout dalam tim SPV.', 'range', public.get_default_low_sellout_score_config(), 10, 90, true),
  ('sator', 'kpi_ma', 'KPI MA', 'Penilaian subjektif dari MA.', 'manual', '{}'::jsonb, 0, 100, true)
on conflict (role, metric_code) do update
set
  display_name = excluded.display_name,
  description = excluded.description,
  score_source = excluded.score_source,
  score_config = excluded.score_config,
  updated_at = now();

create or replace function public.ensure_kpi_period_settings(
  p_period_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path to public
as $$
begin
  if p_period_id is null or coalesce(p_role, '') = '' then
    return;
  end if;

  if exists (
    select 1
    from public.kpi_period_settings kps
    where kps.period_id = p_period_id
      and kps.role = p_role
  ) then
    return;
  end if;

  insert into public.kpi_period_settings (
    period_id,
    role,
    template_id,
    metric_code,
    display_name,
    description,
    score_source,
    score_config,
    weight,
    sort_order,
    is_active
  )
  select
    p_period_id,
    kmt.role,
    kmt.id,
    kmt.metric_code,
    kmt.display_name,
    kmt.description,
    kmt.score_source,
    kmt.score_config,
    kmt.default_weight,
    kmt.sort_order,
    kmt.is_active
  from public.kpi_metric_templates kmt
  where kmt.role = p_role
    and kmt.is_active = true
  on conflict (period_id, role, metric_code) do nothing;
end;
$$;

grant execute on function public.ensure_kpi_period_settings(uuid, text) to authenticated;

create or replace function public.get_kpi_period_settings(
  p_period_id uuid,
  p_role text
)
returns table(
  id uuid,
  period_id uuid,
  role text,
  template_id uuid,
  metric_code text,
  display_name text,
  description text,
  score_source text,
  score_config jsonb,
  weight integer,
  sort_order integer,
  is_active boolean
)
language plpgsql
security definer
set search_path to public
as $$
begin
  perform public.ensure_kpi_period_settings(p_period_id, p_role);

  return query
  select
    kps.id,
    kps.period_id,
    kps.role,
    kps.template_id,
    kps.metric_code,
    kps.display_name,
    kps.description,
    kps.score_source,
    kps.score_config,
    kps.weight,
    kps.sort_order,
    kps.is_active
  from public.kpi_period_settings kps
  where kps.period_id = p_period_id
    and kps.role = p_role
    and kps.is_active = true
  order by kps.sort_order, kps.display_name;
end;
$$;

grant execute on function public.get_kpi_period_settings(uuid, text) to authenticated;

create or replace function public.evaluate_kpi_range_score(
  p_score_config jsonb,
  p_value numeric
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_row jsonb;
  v_min numeric;
  v_max numeric;
  v_score numeric;
begin
  for v_row in
    select value
    from jsonb_array_elements(coalesce(p_score_config->'ranges', '[]'::jsonb))
  loop
    v_min := coalesce(nullif(v_row->>'min_pct', '')::numeric, 0);
    v_max := nullif(v_row->>'max_pct', '')::numeric;
    v_score := coalesce(nullif(v_row->>'score', '')::numeric, 0);
    if p_value >= v_min and (v_max is null or p_value <= v_max) then
      return v_score;
    end if;
  end loop;
  return 0;
end;
$$;

create or replace function public.get_low_sellout_metrics(
  p_role text,
  p_actor_id uuid,
  p_period_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_start date;
  v_end date;
  v_total integer := 0;
  v_low integer := 0;
  v_pct numeric := 0;
  v_score numeric := 0;
  v_config jsonb := public.get_default_low_sellout_score_config();
begin
  select tp.start_date, tp.end_date
  into v_start, v_end
  from public.target_periods tp
  where tp.id = p_period_id
  limit 1;

  if v_start is null or v_end is null then
    return jsonb_build_object(
      'total_promotor', 0,
      'low_sellout_count', 0,
      'low_sellout_pct', 0,
      'score', 0
    );
  end if;

  if p_role = 'sator' then
    with promotor_scope as (
      select u.id, coalesce(u.promotor_status, 'official') as promotor_status
      from public.hierarchy_sator_promotor hsp
      join public.users u on u.id = hsp.promotor_id
      where hsp.sator_id = p_actor_id
        and hsp.active = true
        and u.deleted_at is null
    ),
    monthly_sellout as (
      select
        ps.id as promotor_id,
        ps.promotor_status,
        coalesce(dpm.total_omzet_real, 0)::numeric as actual_sellout
      from promotor_scope ps
      left join public.dashboard_performance_metrics dpm
        on dpm.user_id = ps.id
       and dpm.period_id = p_period_id
    )
    select
      count(*)::int,
      count(*) filter (
        where actual_sellout <
          case
            when promotor_status = 'training' then 60000000
            else 120000000
          end
      )::int
    into v_total, v_low
    from monthly_sellout;
  elsif p_role = 'spv' then
    with promotor_scope as (
      select u.id, coalesce(u.promotor_status, 'official') as promotor_status
      from public.hierarchy_spv_sator hss
      join public.hierarchy_sator_promotor hsp
        on hsp.sator_id = hss.sator_id
       and hsp.active = true
      join public.users u on u.id = hsp.promotor_id
      where hss.spv_id = p_actor_id
        and hss.active = true
        and u.deleted_at is null
    ),
    monthly_sellout as (
      select
        ps.id as promotor_id,
        ps.promotor_status,
        coalesce(dpm.total_omzet_real, 0)::numeric as actual_sellout
      from promotor_scope ps
      left join public.dashboard_performance_metrics dpm
        on dpm.user_id = ps.id
       and dpm.period_id = p_period_id
    )
    select
      count(*)::int,
      count(*) filter (
        where actual_sellout <
          case
            when promotor_status = 'training' then 60000000
            else 120000000
          end
      )::int
    into v_total, v_low
    from monthly_sellout;
  end if;

  if v_total > 0 then
    v_pct := round((v_low::numeric / v_total::numeric) * 100, 2);
  end if;
  v_score := public.evaluate_kpi_range_score(v_config, v_pct);

  return jsonb_build_object(
    'total_promotor', coalesce(v_total, 0),
    'low_sellout_count', coalesce(v_low, 0),
    'low_sellout_pct', coalesce(v_pct, 0),
    'score', coalesce(v_score, 0)
  );
end;
$$;

grant execute on function public.get_low_sellout_metrics(text, uuid, uuid) to authenticated;

create or replace function public.get_special_rewards_by_role(
  p_role text
)
returns json
language plpgsql
security definer
set search_path to public
as $$
declare
  v_period_id uuid;
begin
  select tp.id
  into v_period_id
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  return (
    select coalesce(
      json_agg(
        json_build_object(
          'id', src.id,
          'role', src.role,
          'reward_amount', src.reward_amount,
          'penalty_threshold', src.penalty_threshold,
          'penalty_amount', src.penalty_amount,
          'description', src.description,
          'special_bundle_name', src.bundle_name
        )
        order by src.bundle_name
      ),
      '[]'::json
    )
    from (
      select
        src.id,
        src.role,
        src.reward_amount,
        src.penalty_threshold,
        src.penalty_amount,
        src.description,
        sb.bundle_name
      from public.special_reward_configs src
      join public.special_focus_bundles sb on sb.id = src.special_bundle_id
      where src.role = p_role
        and src.period_id = v_period_id
    ) src
  );
end;
$$;

create or replace function public.get_sator_kpi_summary(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path to public
as $$
declare
  v_result json;
  v_period_id uuid;
  v_start date;
  v_end date;
  v_target_sellout numeric := 0;
  v_target_fokus numeric := 0;
  v_target_sellin numeric := 0;
  v_actual_sellout numeric := 0;
  v_actual_fokus numeric := 0;
  v_actual_sellin numeric := 0;
  v_ma_score numeric := 0;
  v_low_sellout_score numeric := 0;
  v_low_sellout_pct numeric := 0;
  v_low_sellout_count integer := 0;
  v_total_promotor integer := 0;
  v_sellout_score numeric := 0;
  v_fokus_score numeric := 0;
  v_sellin_score numeric := 0;
  v_total_score numeric := 0;
begin
  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  if v_period_id is null then
    return json_build_object(
      'sell_out_all_score', 0,
      'sell_out_fokus_score', 0,
      'sell_in_score', 0,
      'kpi_ma_score', 0,
      'low_sellout_score', 0,
      'low_sellout_pct', 0,
      'low_sellout_count', 0,
      'total_promotor', 0,
      'total_score', 0,
      'total_bonus', 0
    );
  end if;

  select
    coalesce(ut.target_sell_out, 0),
    coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0),
    coalesce(ut.target_sell_in, 0)
  into v_target_sellout, v_target_fokus, v_target_sellin
  from public.user_targets ut
  where ut.user_id = p_sator_id
    and ut.period_id = v_period_id
  order by ut.updated_at desc
  limit 1;

  select
    coalesce(sum(dpm.total_omzet_real), 0),
    coalesce(sum(dpm.total_units_focus), 0)
  into v_actual_sellout, v_actual_fokus
  from public.dashboard_performance_metrics dpm
  where dpm.period_id = v_period_id
    and dpm.user_id in (
      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      where hsp.sator_id = p_sator_id
        and hsp.active = true
    );

  select coalesce(sum(ssi.total_value), 0)
  into v_actual_sellin
  from public.sales_sell_in ssi
  where ssi.sator_id = p_sator_id
    and ssi.transaction_date between v_start and v_end
    and ssi.deleted_at is null;

  select coalesce(public.get_sator_kpi_ma(p_sator_id, v_start), 0)
  into v_ma_score;

  select
    coalesce((payload->>'score')::numeric, 0),
    coalesce((payload->>'low_sellout_pct')::numeric, 0),
    coalesce((payload->>'low_sellout_count')::int, 0),
    coalesce((payload->>'total_promotor')::int, 0)
  into v_low_sellout_score, v_low_sellout_pct, v_low_sellout_count, v_total_promotor
  from (
    select public.get_low_sellout_metrics('sator', p_sator_id, v_period_id) as payload
  ) x;

  v_sellout_score := case when v_target_sellout > 0 then least((v_actual_sellout * 100 / v_target_sellout), 100) else 0 end;
  v_fokus_score := case when v_target_fokus > 0 then least((v_actual_fokus * 100 / v_target_fokus), 100) else 0 end;
  v_sellin_score := case when v_target_sellin > 0 then least((v_actual_sellin * 100 / v_target_sellin), 100) else 0 end;

  select coalesce(sum(
    case kps.metric_code
      when 'sell_out_all' then kps.weight * v_sellout_score
      when 'sell_out_focus' then kps.weight * v_fokus_score
      when 'sell_in_all' then kps.weight * v_sellin_score
      when 'kpi_ma' then kps.weight * v_ma_score
      when 'low_sellout' then kps.weight * v_low_sellout_score
      else 0
    end
  ) / 100, 0)
  into v_total_score
  from public.get_kpi_period_settings(v_period_id, 'sator') kps;

  v_result := json_build_object(
    'period_id', v_period_id,
    'sell_out_all_score', v_sellout_score,
    'sell_out_fokus_score', v_fokus_score,
    'sell_in_score', v_sellin_score,
    'kpi_ma_score', v_ma_score,
    'low_sellout_score', v_low_sellout_score,
    'low_sellout_pct', v_low_sellout_pct,
    'low_sellout_count', v_low_sellout_count,
    'total_promotor', v_total_promotor,
    'total_score', v_total_score,
    'total_bonus', 0
  );
  return v_result;
end;
$$;

create or replace function public.get_spv_kpi_summary(p_spv_id uuid)
returns json
language plpgsql
security definer
set search_path to public
as $$
declare
  v_result json;
  v_period_id uuid;
  v_start date;
  v_end date;
  v_target_sellout numeric := 0;
  v_target_fokus numeric := 0;
  v_target_sellin numeric := 0;
  v_actual_sellout numeric := 0;
  v_actual_fokus numeric := 0;
  v_actual_sellin numeric := 0;
  v_ma_score numeric := 0;
  v_low_sellout_score numeric := 0;
  v_low_sellout_pct numeric := 0;
  v_low_sellout_count integer := 0;
  v_total_promotor integer := 0;
  v_sellout_score numeric := 0;
  v_fokus_score numeric := 0;
  v_sellin_score numeric := 0;
  v_total_score numeric := 0;
  v_total_bonus numeric := 0;
begin
  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  if v_period_id is null then
    return json_build_object(
      'sell_out_all_score', 0,
      'sell_out_fokus_score', 0,
      'sell_in_score', 0,
      'kpi_ma_score', 0,
      'low_sellout_score', 0,
      'low_sellout_pct', 0,
      'low_sellout_count', 0,
      'total_promotor', 0,
      'total_score', 0,
      'total_bonus', 0
    );
  end if;

  select
    coalesce(ut.target_sell_out, 0),
    coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0),
    coalesce(ut.target_sell_in, 0)
  into v_target_sellout, v_target_fokus, v_target_sellin
  from public.user_targets ut
  where ut.user_id = p_spv_id
    and ut.period_id = v_period_id
  order by ut.updated_at desc
  limit 1;

  if v_target_sellout = 0 or v_target_fokus = 0 then
    select
      coalesce(sum(ut.target_omzet), 0),
      coalesce(sum(ut.target_fokus_total), 0)
    into v_target_sellout, v_target_fokus
    from public.user_targets ut
    where ut.period_id = v_period_id
      and ut.user_id in (
        select hsp.promotor_id
        from public.hierarchy_sator_promotor hsp
        join public.hierarchy_spv_sator hss
          on hss.sator_id = hsp.sator_id
         and hss.active = true
        where hss.spv_id = p_spv_id
          and hsp.active = true
      );
  end if;

  select
    coalesce(sum(dpm.total_omzet_real), 0),
    coalesce(sum(dpm.total_units_focus), 0),
    coalesce(sum(dpm.estimated_bonus_total), 0)
  into v_actual_sellout, v_actual_fokus, v_total_bonus
  from public.dashboard_performance_metrics dpm
  where dpm.period_id = v_period_id
    and dpm.user_id in (
      select hsp.promotor_id
      from public.hierarchy_sator_promotor hsp
      join public.hierarchy_spv_sator hss
        on hss.sator_id = hsp.sator_id
       and hss.active = true
      where hss.spv_id = p_spv_id
        and hsp.active = true
    );

  select coalesce(sum(si.total_value), 0)
  into v_actual_sellin
  from public.sales_sell_in si
  where si.transaction_date between v_start and v_end
    and si.deleted_at is null
    and si.sator_id in (
      select hss.sator_id
      from public.hierarchy_spv_sator hss
      where hss.spv_id = p_spv_id
        and hss.active = true
    );

  select coalesce(avg(score), 0)
  into v_ma_score
  from public.kpi_ma_scores
  where period_date = v_start
    and sator_id in (
      select hss.sator_id
      from public.hierarchy_spv_sator hss
      where hss.spv_id = p_spv_id
        and hss.active = true
    );

  select
    coalesce((payload->>'score')::numeric, 0),
    coalesce((payload->>'low_sellout_pct')::numeric, 0),
    coalesce((payload->>'low_sellout_count')::int, 0),
    coalesce((payload->>'total_promotor')::int, 0)
  into v_low_sellout_score, v_low_sellout_pct, v_low_sellout_count, v_total_promotor
  from (
    select public.get_low_sellout_metrics('spv', p_spv_id, v_period_id) as payload
  ) x;

  v_sellout_score := case when v_target_sellout > 0 then least((v_actual_sellout * 100 / v_target_sellout), 100) else 0 end;
  v_fokus_score := case when v_target_fokus > 0 then least((v_actual_fokus * 100 / v_target_fokus), 100) else 0 end;
  v_sellin_score := case when v_target_sellin > 0 then least((v_actual_sellin * 100 / v_target_sellin), 100) else 0 end;

  select coalesce(sum(
    case kps.metric_code
      when 'sell_out_all' then kps.weight * v_sellout_score
      when 'sell_out_focus' then kps.weight * v_fokus_score
      when 'sell_in_all' then kps.weight * v_sellin_score
      when 'kpi_ma' then kps.weight * v_ma_score
      when 'low_sellout' then kps.weight * v_low_sellout_score
      else 0
    end
  ) / 100, 0)
  into v_total_score
  from public.get_kpi_period_settings(v_period_id, 'spv') kps;

  v_result := json_build_object(
    'period_id', v_period_id,
    'sell_out_all_score', v_sellout_score,
    'sell_out_fokus_score', v_fokus_score,
    'sell_in_score', v_sellin_score,
    'kpi_ma_score', v_ma_score,
    'low_sellout_score', v_low_sellout_score,
    'low_sellout_pct', v_low_sellout_pct,
    'low_sellout_count', v_low_sellout_count,
    'total_promotor', v_total_promotor,
    'total_score', v_total_score,
    'total_bonus', coalesce(v_total_bonus, 0)
  );
  return v_result;
end;
$$;

create or replace function public.get_sator_bonus_detail(p_sator_id uuid)
returns json
language plpgsql
security definer
set search_path to public
as $$
declare
  v_result json;
  v_period_id uuid;
  v_start date;
  v_end date;
  v_period_month text;
  v_kpi json;
  v_total_kpi_score numeric := 0;
  v_kpi_eligible boolean := false;
  v_total_points numeric := 0;
  v_point_value numeric := 1000;
  v_potential_kpi_bonus numeric := 0;
  v_effective_kpi_bonus numeric := 0;
  v_points_breakdown json := '[]'::json;
  v_special_reward_total numeric := 0;
  v_special_penalty_total numeric := 0;
  v_special_bonus numeric := 0;
  v_rewards_breakdown json := '[]'::json;
  v_total_bonus_effective numeric := 0;
  v_total_bonus_potential numeric := 0;
begin
  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  if v_period_id is null then
    return json_build_object(
      'period_month', null,
      'kpi', json_build_object('total_score', 0, 'eligible', false, 'min_required', 80),
      'points', json_build_object('total_points', 0, 'point_value', v_point_value, 'potential_kpi_bonus', 0, 'effective_kpi_bonus', 0),
      'special_rewards', json_build_object('special_bonus_effective', 0, 'reward_total', 0, 'penalty_total', 0, 'breakdown', '[]'::json),
      'totals', json_build_object('total_bonus_effective', 0, 'total_bonus_potential', 0)
    );
  end if;

  v_period_month := to_char(v_start, 'YYYY-MM');
  select public.get_sator_kpi_summary(p_sator_id) into v_kpi;
  v_total_kpi_score := coalesce((v_kpi->>'total_score')::numeric, 0);
  v_kpi_eligible := v_total_kpi_score >= 80;

  with promotor_ids as (
    select hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.active = true
  ),
  sales_with_price as (
    select s.id, s.price_at_transaction
    from public.sales_sell_out s
    join promotor_ids pi on pi.promotor_id = s.promotor_id
    where s.transaction_date between v_start and v_end
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
  ),
  range_counts as (
    select
      pr.id,
      pr.min_price,
      pr.max_price,
      pr.points_per_unit,
      coalesce(count(swp.id), 0) as units
    from public.point_ranges pr
    left join sales_with_price swp
      on swp.price_at_transaction >= pr.min_price
     and (pr.max_price is null or pr.max_price = 0 or swp.price_at_transaction <= pr.max_price)
    where pr.role = 'sator'
      and pr.data_source = 'sell_out'
    group by pr.id, pr.min_price, pr.max_price, pr.points_per_unit
  )
  select
    coalesce(sum(units * points_per_unit), 0),
    coalesce(json_agg(
      json_build_object(
        'min_price', min_price,
        'max_price', max_price,
        'points_per_unit', points_per_unit,
        'units', units,
        'total_points', (units * points_per_unit)
      )
      order by min_price
    ), '[]'::json)
  into v_total_points, v_points_breakdown
  from range_counts;

  v_potential_kpi_bonus := coalesce(v_total_points, 0) * v_point_value;
  v_effective_kpi_bonus := case when v_kpi_eligible then v_potential_kpi_bonus else 0 end;

  with target_rows as (
    select
      sb.id as bundle_id,
      sb.bundle_name,
      (d.value::text)::numeric as target_qty
    from public.user_targets ut
    join lateral jsonb_each(coalesce(ut.target_special_detail, '{}'::jsonb)) d on true
    join public.special_focus_bundles sb
      on sb.id::text = d.key
     and sb.period_id = v_period_id
    where ut.user_id = p_sator_id
      and ut.period_id = v_period_id
  ),
  actual_rows as (
    select
      sbp.bundle_id,
      count(*)::numeric as actual_qty
    from public.sales_sell_out s
    join public.hierarchy_sator_promotor hsp
      on hsp.promotor_id = s.promotor_id
     and hsp.sator_id = p_sator_id
     and hsp.active = true
    join public.product_variants pv on pv.id = s.variant_id
    join public.special_focus_bundle_products sbp on sbp.product_id = pv.product_id
    join public.special_focus_bundles sb on sb.id = sbp.bundle_id and sb.period_id = v_period_id
    where s.transaction_date between v_start and v_end
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
    group by sbp.bundle_id
  ),
  cfg as (
    select
      src.special_bundle_id as bundle_id,
      src.reward_amount,
      src.penalty_threshold,
      src.penalty_amount
    from public.special_reward_configs src
    where src.period_id = v_period_id
      and src.role = 'sator'
  ),
  calc as (
    select
      tr.bundle_id,
      tr.bundle_name,
      tr.target_qty,
      coalesce(ar.actual_qty, 0) as actual_qty,
      coalesce(cfg.reward_amount, 0) as reward_amount,
      coalesce(cfg.penalty_threshold, 80) as penalty_threshold,
      coalesce(cfg.penalty_amount, 0) as penalty_amount,
      case
        when tr.target_qty > 0 then round((coalesce(ar.actual_qty, 0) / tr.target_qty) * 100, 2)
        else 0
      end as achievement_pct
    from target_rows tr
    left join actual_rows ar on ar.bundle_id = tr.bundle_id
    left join cfg on cfg.bundle_id = tr.bundle_id
  )
  select
    coalesce(sum(case when actual_qty >= target_qty and target_qty > 0 then reward_amount else 0 end), 0),
    coalesce(sum(case when target_qty > 0 and achievement_pct < penalty_threshold then penalty_amount else 0 end), 0),
    coalesce(json_agg(
      json_build_object(
        'bundle_id', bundle_id,
        'name', bundle_name,
        'target_qty', target_qty,
        'actual_units', actual_qty,
        'achievement_pct', achievement_pct,
        'reward_amount', reward_amount,
        'penalty_threshold', penalty_threshold,
        'penalty_amount', penalty_amount,
        'reward_effective', case when actual_qty >= target_qty and target_qty > 0 then reward_amount else 0 end,
        'penalty_effective', case when target_qty > 0 and achievement_pct < penalty_threshold then penalty_amount else 0 end,
        'eligible', (actual_qty >= target_qty and target_qty > 0),
        'net_bonus',
          (case when actual_qty >= target_qty and target_qty > 0 then reward_amount else 0 end)
          - (case when target_qty > 0 and achievement_pct < penalty_threshold then penalty_amount else 0 end)
      )
      order by bundle_name
    ), '[]'::json)
  into v_special_reward_total, v_special_penalty_total, v_rewards_breakdown
  from calc;

  v_special_bonus := coalesce(v_special_reward_total, 0) - coalesce(v_special_penalty_total, 0);
  v_total_bonus_effective := v_effective_kpi_bonus + v_special_bonus;
  v_total_bonus_potential := v_potential_kpi_bonus + v_special_bonus;

  v_result := json_build_object(
    'period_month', v_period_month,
    'kpi', json_build_object('total_score', v_total_kpi_score, 'eligible', v_kpi_eligible, 'min_required', 80),
    'points', json_build_object(
      'total_points', coalesce(v_total_points, 0),
      'point_value', v_point_value,
      'potential_kpi_bonus', v_potential_kpi_bonus,
      'effective_kpi_bonus', v_effective_kpi_bonus,
      'breakdown', v_points_breakdown
    ),
    'special_rewards', json_build_object(
      'special_bonus_effective', v_special_bonus,
      'reward_total', coalesce(v_special_reward_total, 0),
      'penalty_total', coalesce(v_special_penalty_total, 0),
      'breakdown', v_rewards_breakdown
    ),
    'totals', json_build_object(
      'total_bonus_effective', v_total_bonus_effective,
      'total_bonus_potential', v_total_bonus_potential
    )
  );
  return v_result;
end;
$$;

create or replace function public.get_spv_bonus_detail(p_spv_id uuid)
returns json
language plpgsql
security definer
set search_path to public
as $$
declare
  v_result json;
  v_period_id uuid;
  v_start date;
  v_end date;
  v_period_month text;
  v_kpi json;
  v_total_kpi_score numeric := 0;
  v_kpi_eligible boolean := false;
  v_total_points numeric := 0;
  v_point_value numeric := 1000;
  v_potential_kpi_bonus numeric := 0;
  v_effective_kpi_bonus numeric := 0;
  v_points_breakdown json := '[]'::json;
  v_special_reward_total numeric := 0;
  v_special_penalty_total numeric := 0;
  v_special_bonus numeric := 0;
  v_rewards_breakdown json := '[]'::json;
  v_total_bonus_effective numeric := 0;
  v_total_bonus_potential numeric := 0;
begin
  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start, v_end
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  if v_period_id is null then
    return json_build_object(
      'period_month', null,
      'kpi', json_build_object('total_score', 0, 'eligible', false, 'min_required', 80),
      'points', json_build_object('total_points', 0, 'point_value', v_point_value, 'potential_kpi_bonus', 0, 'effective_kpi_bonus', 0),
      'special_rewards', json_build_object('special_bonus_effective', 0, 'reward_total', 0, 'penalty_total', 0, 'breakdown', '[]'::json),
      'totals', json_build_object('total_bonus_effective', 0, 'total_bonus_potential', 0)
    );
  end if;

  v_period_month := to_char(v_start, 'YYYY-MM');
  select public.get_spv_kpi_summary(p_spv_id) into v_kpi;
  v_total_kpi_score := coalesce((v_kpi->>'total_score')::numeric, 0);
  v_kpi_eligible := v_total_kpi_score >= 80;

  with promotor_scope as (
    select hsp.promotor_id
    from public.hierarchy_spv_sator hss
    join public.hierarchy_sator_promotor hsp
      on hsp.sator_id = hss.sator_id
     and hsp.active = true
    where hss.spv_id = p_spv_id
      and hss.active = true
  ),
  sales_with_price as (
    select s.id, s.price_at_transaction
    from public.sales_sell_out s
    join promotor_scope ps on ps.promotor_id = s.promotor_id
    where s.transaction_date between v_start and v_end
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
  ),
  range_counts as (
    select
      pr.id,
      pr.min_price,
      pr.max_price,
      pr.points_per_unit,
      coalesce(count(swp.id), 0) as units
    from public.point_ranges pr
    left join sales_with_price swp
      on swp.price_at_transaction >= pr.min_price
     and (pr.max_price is null or pr.max_price = 0 or swp.price_at_transaction <= pr.max_price)
    where pr.role = 'spv'
      and pr.data_source = 'sell_out'
    group by pr.id, pr.min_price, pr.max_price, pr.points_per_unit
  )
  select
    coalesce(sum(units * points_per_unit), 0),
    coalesce(json_agg(
      json_build_object(
        'min_price', min_price,
        'max_price', max_price,
        'points_per_unit', points_per_unit,
        'units', units,
        'total_points', (units * points_per_unit)
      )
      order by min_price
    ), '[]'::json)
  into v_total_points, v_points_breakdown
  from range_counts;

  v_potential_kpi_bonus := coalesce(v_total_points, 0) * v_point_value;
  v_effective_kpi_bonus := case when v_kpi_eligible then v_potential_kpi_bonus else 0 end;

  with target_rows as (
    select
      sb.id as bundle_id,
      sb.bundle_name,
      (d.value::text)::numeric as target_qty
    from public.user_targets ut
    join lateral jsonb_each(coalesce(ut.target_special_detail, '{}'::jsonb)) d on true
    join public.special_focus_bundles sb
      on sb.id::text = d.key
     and sb.period_id = v_period_id
    where ut.user_id = p_spv_id
      and ut.period_id = v_period_id
  ),
  actual_rows as (
    select
      sbp.bundle_id,
      count(*)::numeric as actual_qty
    from public.sales_sell_out s
    join public.hierarchy_spv_sator hss
      on hss.spv_id = p_spv_id
     and hss.active = true
    join public.hierarchy_sator_promotor hsp
      on hsp.sator_id = hss.sator_id
     and hsp.active = true
     and hsp.promotor_id = s.promotor_id
    join public.product_variants pv on pv.id = s.variant_id
    join public.special_focus_bundle_products sbp on sbp.product_id = pv.product_id
    join public.special_focus_bundles sb on sb.id = sbp.bundle_id and sb.period_id = v_period_id
    where s.transaction_date between v_start and v_end
      and s.deleted_at is null
      and coalesce(s.is_chip_sale, false) = false
    group by sbp.bundle_id
  ),
  cfg as (
    select
      src.special_bundle_id as bundle_id,
      src.reward_amount,
      src.penalty_threshold,
      src.penalty_amount
    from public.special_reward_configs src
    where src.period_id = v_period_id
      and src.role = 'spv'
  ),
  calc as (
    select
      tr.bundle_id,
      tr.bundle_name,
      tr.target_qty,
      coalesce(ar.actual_qty, 0) as actual_qty,
      coalesce(cfg.reward_amount, 0) as reward_amount,
      coalesce(cfg.penalty_threshold, 80) as penalty_threshold,
      coalesce(cfg.penalty_amount, 0) as penalty_amount,
      case
        when tr.target_qty > 0 then round((coalesce(ar.actual_qty, 0) / tr.target_qty) * 100, 2)
        else 0
      end as achievement_pct
    from target_rows tr
    left join actual_rows ar on ar.bundle_id = tr.bundle_id
    left join cfg on cfg.bundle_id = tr.bundle_id
  )
  select
    coalesce(sum(case when actual_qty >= target_qty and target_qty > 0 then reward_amount else 0 end), 0),
    coalesce(sum(case when target_qty > 0 and achievement_pct < penalty_threshold then penalty_amount else 0 end), 0),
    coalesce(json_agg(
      json_build_object(
        'bundle_id', bundle_id,
        'name', bundle_name,
        'target_qty', target_qty,
        'actual_units', actual_qty,
        'achievement_pct', achievement_pct,
        'reward_amount', reward_amount,
        'penalty_threshold', penalty_threshold,
        'penalty_amount', penalty_amount,
        'reward_effective', case when actual_qty >= target_qty and target_qty > 0 then reward_amount else 0 end,
        'penalty_effective', case when target_qty > 0 and achievement_pct < penalty_threshold then penalty_amount else 0 end,
        'eligible', (actual_qty >= target_qty and target_qty > 0),
        'net_bonus',
          (case when actual_qty >= target_qty and target_qty > 0 then reward_amount else 0 end)
          - (case when target_qty > 0 and achievement_pct < penalty_threshold then penalty_amount else 0 end)
      )
      order by bundle_name
    ), '[]'::json)
  into v_special_reward_total, v_special_penalty_total, v_rewards_breakdown
  from calc;

  v_special_bonus := coalesce(v_special_reward_total, 0) - coalesce(v_special_penalty_total, 0);
  v_total_bonus_effective := v_effective_kpi_bonus + v_special_bonus;
  v_total_bonus_potential := v_potential_kpi_bonus + v_special_bonus;

  v_result := json_build_object(
    'period_month', v_period_month,
    'kpi', json_build_object('total_score', v_total_kpi_score, 'eligible', v_kpi_eligible, 'min_required', 80),
    'points', json_build_object(
      'total_points', coalesce(v_total_points, 0),
      'point_value', v_point_value,
      'potential_kpi_bonus', v_potential_kpi_bonus,
      'effective_kpi_bonus', v_effective_kpi_bonus,
      'breakdown', v_points_breakdown
    ),
    'special_rewards', json_build_object(
      'special_bonus_effective', v_special_bonus,
      'reward_total', coalesce(v_special_reward_total, 0),
      'penalty_total', coalesce(v_special_penalty_total, 0),
      'breakdown', v_rewards_breakdown
    ),
    'totals', json_build_object(
      'total_bonus_effective', v_total_bonus_effective,
      'total_bonus_potential', v_total_bonus_potential
    )
  );
  return v_result;
end;
$$;

create or replace function public.get_spv_kpi_page_snapshot(p_spv_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_period_id uuid;
  v_start_date date;
  v_end_date date;
  v_kpi jsonb := '{}'::jsonb;
  v_kpi_detail jsonb := '{}'::jsonb;
  v_components jsonb := '[]'::jsonb;
  v_point_ranges jsonb := '[]'::jsonb;
  v_special_rewards jsonb := '[]'::jsonb;
  v_bonus_detail jsonb := '{}'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_spv_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start_date, v_end_date
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  v_kpi := coalesce(public.get_spv_kpi_summary(p_spv_id)::jsonb, '{}'::jsonb);

  with target_row as (
    select
      coalesce(ut.target_sell_out, 0)::numeric as target_sellout,
      coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)::numeric as target_fokus,
      coalesce(ut.target_sell_in, 0)::numeric as target_sellin
    from public.user_targets ut
    where ut.user_id = p_spv_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc
    limit 1
  ),
  promotor_scope as (
    select hsp.promotor_id
    from public.hierarchy_spv_sator hss
    join public.hierarchy_sator_promotor hsp
      on hsp.sator_id = hss.sator_id
     and hsp.active = true
    where hss.spv_id = p_spv_id
      and hss.active = true
  ),
  metrics_rollup as (
    select
      coalesce(sum(dpm.total_omzet_real), 0)::numeric as actual_sellout,
      coalesce(sum(dpm.total_units_focus), 0)::numeric as actual_fokus
    from public.dashboard_performance_metrics dpm
    where dpm.user_id in (select promotor_id from promotor_scope)
      and dpm.period_id = v_period_id
  ),
  sellin_rollup as (
    select coalesce(sum(ssi.total_value), 0)::numeric as actual_sellin
    from public.sales_sell_in ssi
    where ssi.sator_id in (
      select hss.sator_id
      from public.hierarchy_spv_sator hss
      where hss.spv_id = p_spv_id
        and hss.active = true
    )
      and (v_start_date is null or ssi.transaction_date >= v_start_date)
      and (v_end_date is null or ssi.transaction_date <= v_end_date)
      and ssi.deleted_at is null
  ),
  kpi_ma_row as (
    select coalesce(avg(km.score), 0)::numeric as kpi_ma
    from public.kpi_ma_scores km
    where km.sator_id in (
      select hss.sator_id
      from public.hierarchy_spv_sator hss
      where hss.spv_id = p_spv_id
        and hss.active = true
    )
      and km.period_date = v_start_date
  ),
  low_sellout_row as (
    select public.get_low_sellout_metrics('spv', p_spv_id, v_period_id) as payload
  )
  select jsonb_build_object(
    'target_sellout', coalesce(tr.target_sellout, 0),
    'target_fokus', coalesce(tr.target_fokus, 0),
    'target_sellin', coalesce(tr.target_sellin, 0),
    'actual_sellout', coalesce(mr.actual_sellout, 0),
    'actual_fokus', coalesce(mr.actual_fokus, 0),
    'actual_sellin', coalesce(sr.actual_sellin, 0),
    'kpi_ma', coalesce(km.kpi_ma, 0),
    'low_sellout_pct', coalesce((ls.payload->>'low_sellout_pct')::numeric, 0),
    'low_sellout_count', coalesce((ls.payload->>'low_sellout_count')::int, 0),
    'total_promotor', coalesce((ls.payload->>'total_promotor')::int, 0)
  )
  into v_kpi_detail
  from target_row tr
  full join metrics_rollup mr on true
  full join sellin_rollup sr on true
  full join kpi_ma_row km on true
  full join low_sellout_row ls on true;

  with settings as (
    select *
    from public.get_kpi_period_settings(v_period_id, 'spv')
  ),
  totals as (
    select coalesce(sum(weight), 0)::numeric as total_weight
    from settings
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', s.display_name,
        'metricCode', s.metric_code,
        'rawWeight', s.weight,
        'weight', case when t.total_weight > 0 then (s.weight * 100 / t.total_weight) else 0 end,
        'score', case s.metric_code
          when 'sell_out_all' then coalesce((v_kpi->>'sell_out_all_score')::numeric, 0)
          when 'sell_out_focus' then coalesce((v_kpi->>'sell_out_fokus_score')::numeric, 0)
          when 'sell_in_all' then coalesce((v_kpi->>'sell_in_score')::numeric, 0)
          when 'kpi_ma' then coalesce((v_kpi->>'kpi_ma_score')::numeric, 0)
          when 'low_sellout' then coalesce((v_kpi->>'low_sellout_score')::numeric, 0)
          else 0
        end
      )
      order by s.sort_order, s.display_name
    ),
    '[]'::jsonb
  )
  into v_components
  from settings s
  cross join totals t;

  select coalesce(jsonb_agg(to_jsonb(pr) order by pr.data_source, pr.min_price), '[]'::jsonb)
  into v_point_ranges
  from (
    select min_price, max_price, points_per_unit, data_source
    from public.point_ranges
    where role = 'spv'
    order by data_source, min_price
  ) pr;

  v_special_rewards := coalesce(public.get_special_rewards_by_role('spv')::jsonb, '[]'::jsonb);
  v_bonus_detail := coalesce(public.get_spv_bonus_detail(p_spv_id)::jsonb, '{}'::jsonb);

  return jsonb_build_object(
    'kpi_data', coalesce(v_kpi, '{}'::jsonb),
    'kpi_components', v_components,
    'kpi_detail', coalesce(v_kpi_detail, '{}'::jsonb),
    'point_ranges', v_point_ranges,
    'special_rewards', v_special_rewards,
    'bonus_detail', v_bonus_detail
  );
end;
$$;

create or replace function public.get_sator_kpi_page_snapshot(p_sator_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_period_id uuid;
  v_start_date date;
  v_end_date date;
  v_kpi jsonb := '{}'::jsonb;
  v_kpi_detail jsonb := '{}'::jsonb;
  v_point_ranges jsonb := '[]'::jsonb;
  v_special_rewards jsonb := '[]'::jsonb;
  v_rewards jsonb := '[]'::jsonb;
  v_bonus_detail jsonb := '{}'::jsonb;
  v_components jsonb := '[]'::jsonb;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sator_id is distinct from v_actor_id and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  select tp.id, tp.start_date, tp.end_date
  into v_period_id, v_start_date, v_end_date
  from public.target_periods tp
  where tp.start_date <= current_date
    and tp.end_date >= current_date
  order by case when tp.status = 'active' then 0 else 1 end, tp.start_date desc
  limit 1;

  v_kpi := coalesce(public.get_sator_kpi_summary(p_sator_id)::jsonb, '{}'::jsonb);

  with target_row as (
    select
      coalesce(ut.target_sell_out, 0)::numeric as target_sellout,
      coalesce(nullif(ut.target_fokus_total, 0), ut.target_fokus, 0)::numeric as target_fokus,
      coalesce(ut.target_sell_in, 0)::numeric as target_sellin
    from public.user_targets ut
    where ut.user_id = p_sator_id
      and ut.period_id = v_period_id
    order by ut.updated_at desc
    limit 1
  ),
  promotor_scope as (
    select hsp.promotor_id
    from public.hierarchy_sator_promotor hsp
    where hsp.sator_id = p_sator_id
      and hsp.active = true
  ),
  metrics_rollup as (
    select
      coalesce(sum(dpm.total_omzet_real), 0)::numeric as actual_sellout,
      coalesce(sum(dpm.total_units_focus), 0)::numeric as actual_fokus
    from public.dashboard_performance_metrics dpm
    where dpm.user_id in (select promotor_id from promotor_scope)
      and dpm.period_id = v_period_id
  ),
  sellin_rollup as (
    select coalesce(sum(ssi.total_value), 0)::numeric as actual_sellin
    from public.sales_sell_in ssi
    where ssi.sator_id = p_sator_id
      and (v_start_date is null or ssi.transaction_date >= v_start_date)
      and (v_end_date is null or ssi.transaction_date <= v_end_date)
      and ssi.deleted_at is null
  ),
  kpi_ma_row as (
    select coalesce(km.score, 0)::numeric as kpi_ma
    from public.kpi_ma_scores km
    where km.sator_id = p_sator_id
      and km.period_date = v_start_date
    limit 1
  ),
  low_sellout_row as (
    select public.get_low_sellout_metrics('sator', p_sator_id, v_period_id) as payload
  )
  select jsonb_build_object(
    'target_sellout', coalesce(tr.target_sellout, 0),
    'target_fokus', coalesce(tr.target_fokus, 0),
    'target_sellin', coalesce(tr.target_sellin, 0),
    'actual_sellout', coalesce(mr.actual_sellout, 0),
    'actual_fokus', coalesce(mr.actual_fokus, 0),
    'actual_sellin', coalesce(sr.actual_sellin, 0),
    'kpi_ma', coalesce(km.kpi_ma, 0),
    'low_sellout_pct', coalesce((ls.payload->>'low_sellout_pct')::numeric, 0),
    'low_sellout_count', coalesce((ls.payload->>'low_sellout_count')::int, 0),
    'total_promotor', coalesce((ls.payload->>'total_promotor')::int, 0)
  )
  into v_kpi_detail
  from target_row tr
  full join metrics_rollup mr on true
  full join sellin_rollup sr on true
  full join kpi_ma_row km on true
  full join low_sellout_row ls on true;

  with settings as (
    select *
    from public.get_kpi_period_settings(v_period_id, 'sator')
  ),
  totals as (
    select coalesce(sum(weight), 0)::numeric as total_weight
    from settings
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'name', s.display_name,
        'metricCode', s.metric_code,
        'rawWeight', s.weight,
        'weight', case when t.total_weight > 0 then (s.weight * 100 / t.total_weight) else 0 end,
        'score', case s.metric_code
          when 'sell_out_all' then coalesce((v_kpi->>'sell_out_all_score')::numeric, 0)
          when 'sell_out_focus' then coalesce((v_kpi->>'sell_out_fokus_score')::numeric, 0)
          when 'sell_in_all' then coalesce((v_kpi->>'sell_in_score')::numeric, 0)
          when 'kpi_ma' then coalesce((v_kpi->>'kpi_ma_score')::numeric, 0)
          when 'low_sellout' then coalesce((v_kpi->>'low_sellout_score')::numeric, 0)
          else 0
        end
      )
      order by s.sort_order, s.display_name
    ),
    '[]'::jsonb
  )
  into v_components
  from settings s
  cross join totals t;

  select coalesce(jsonb_agg(to_jsonb(pr) order by pr.data_source, pr.min_price), '[]'::jsonb)
  into v_point_ranges
  from (
    select min_price, max_price, points_per_unit, data_source
    from public.point_ranges
    where role = 'sator'
    order by data_source, min_price
  ) pr;

  v_special_rewards := coalesce(public.get_special_rewards_by_role('sator')::jsonb, '[]'::jsonb);
  v_rewards := coalesce(public.get_sator_rewards(p_sator_id)::jsonb, '[]'::jsonb);
  v_bonus_detail := coalesce(public.get_sator_bonus_detail(p_sator_id)::jsonb, '{}'::jsonb);

  return jsonb_build_object(
    'kpi_data', coalesce(v_kpi, '{}'::jsonb),
    'kpi_components', v_components,
    'kpi_detail', coalesce(v_kpi_detail, '{}'::jsonb),
    'point_ranges', v_point_ranges,
    'special_rewards', v_special_rewards,
    'rewards', v_rewards,
    'bonus_detail', v_bonus_detail
  );
end;
$$;

grant execute on function public.get_spv_bonus_detail(uuid) to authenticated;
grant execute on function public.get_sator_kpi_page_snapshot(uuid) to authenticated;
grant execute on function public.get_spv_kpi_page_snapshot(uuid) to authenticated;
