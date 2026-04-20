-- KPI templates stay available, but active metrics for a period must be chosen by admin.

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
    false
  from public.kpi_metric_templates kmt
  where kmt.role = p_role
    and kmt.is_active = true
  on conflict (period_id, role, metric_code) do nothing;
end;
$$;

comment on function public.ensure_kpi_period_settings(uuid, text)
is 'Seed KPI period rows from templates without auto-activating them. Admin chooses active metrics per period.';
