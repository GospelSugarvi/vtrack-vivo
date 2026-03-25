create table if not exists public.vast_agg_weekly_promotor (
  week_start_date date not null,
  week_end_date date not null,
  period_id uuid references public.target_periods(id),
  promotor_id uuid not null references public.users(id),
  store_id uuid references public.stores(id),
  sator_id uuid references public.users(id),
  spv_id uuid references public.users(id),
  target_submissions integer not null default 0,
  total_submissions integer not null default 0,
  total_acc integer not null default 0,
  total_pending integer not null default 0,
  total_reject integer not null default 0,
  total_closed_direct integer not null default 0,
  total_closed_follow_up integer not null default 0,
  total_active_pending integer not null default 0,
  total_duplicate_alerts integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (week_start_date, promotor_id)
);

create table if not exists public.vast_agg_weekly_sator (
  week_start_date date not null,
  week_end_date date not null,
  period_id uuid references public.target_periods(id),
  sator_id uuid not null references public.users(id),
  target_submissions integer not null default 0,
  total_submissions integer not null default 0,
  total_acc integer not null default 0,
  total_pending integer not null default 0,
  total_reject integer not null default 0,
  total_closed_direct integer not null default 0,
  total_closed_follow_up integer not null default 0,
  total_active_pending integer not null default 0,
  total_duplicate_alerts integer not null default 0,
  promotor_with_input integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (week_start_date, sator_id)
);

create table if not exists public.vast_agg_weekly_spv (
  week_start_date date not null,
  week_end_date date not null,
  period_id uuid references public.target_periods(id),
  spv_id uuid not null references public.users(id),
  target_submissions integer not null default 0,
  total_submissions integer not null default 0,
  total_acc integer not null default 0,
  total_pending integer not null default 0,
  total_reject integer not null default 0,
  total_closed_direct integer not null default 0,
  total_closed_follow_up integer not null default 0,
  total_active_pending integer not null default 0,
  total_duplicate_alerts integer not null default 0,
  promotor_with_input integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (week_start_date, spv_id)
);

create or replace function public.vast_week_bounds(p_metric_date date)
returns table(week_start_date date, week_end_date date)
language sql
immutable
as $$
  select
    (date_trunc('week', p_metric_date::timestamp)::date) as week_start_date,
    (date_trunc('week', p_metric_date::timestamp)::date + 6) as week_end_date;
$$;

create or replace function public.vast_refresh_weekly_rollups_for_scope(
  p_promotor_id uuid,
  p_sator_id uuid,
  p_spv_id uuid,
  p_metric_date date,
  p_period_id uuid
)
returns void
language plpgsql
as $$
declare
  v_week_start date;
  v_week_end date;
  v_target integer := 0;
begin
  if p_metric_date is null then
    return;
  end if;

  select week_start_date, week_end_date
    into v_week_start, v_week_end
  from public.vast_week_bounds(p_metric_date);

  if p_promotor_id is not null then
    select coalesce(max(target_vast), 0)
      into v_target
    from public.user_targets
    where user_id = p_promotor_id
      and period_id = p_period_id;

    delete from public.vast_agg_weekly_promotor
    where week_start_date = v_week_start and promotor_id = p_promotor_id;

    insert into public.vast_agg_weekly_promotor (
      week_start_date, week_end_date, period_id, promotor_id, store_id, sator_id, spv_id,
      target_submissions, total_submissions, total_acc, total_pending, total_reject,
      total_closed_direct, total_closed_follow_up, total_active_pending, total_duplicate_alerts, updated_at
    )
    select
      v_week_start,
      v_week_end,
      max(a.period_id),
      a.promotor_id,
      max(a.store_id),
      max(a.sator_id),
      max(a.spv_id),
      ceil(v_target / 4.0)::integer,
      count(*)::integer,
      count(*) filter (where a.outcome_status = 'acc')::integer,
      count(*) filter (where a.outcome_status = 'pending')::integer,
      count(*) filter (where a.outcome_status = 'reject')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_direct')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_follow_up')::integer,
      count(*) filter (where a.lifecycle_status = 'approved_pending')::integer,
      coalesce(sum(a.duplicate_signal_count), 0)::integer,
      now()
    from public.vast_applications a
    where a.promotor_id = p_promotor_id
      and a.application_date between v_week_start and v_week_end
      and a.deleted_at is null
    group by a.promotor_id;
  end if;

  if p_sator_id is not null then
    delete from public.vast_agg_weekly_sator
    where week_start_date = v_week_start and sator_id = p_sator_id;

    insert into public.vast_agg_weekly_sator (
      week_start_date, week_end_date, period_id, sator_id, target_submissions,
      total_submissions, total_acc, total_pending, total_reject, total_closed_direct,
      total_closed_follow_up, total_active_pending, total_duplicate_alerts, promotor_with_input, updated_at
    )
    with team_target as (
      select coalesce(sum(ut.target_vast), 0)::integer as target_submissions
      from public.user_targets ut
      join public.hierarchy_sator_promotor hsp
        on hsp.promotor_id = ut.user_id
       and hsp.sator_id = p_sator_id
       and hsp.active = true
      where ut.period_id = p_period_id
    )
    select
      v_week_start,
      v_week_end,
      max(a.period_id),
      a.sator_id,
      ceil(tt.target_submissions / 4.0)::integer,
      count(*)::integer,
      count(*) filter (where a.outcome_status = 'acc')::integer,
      count(*) filter (where a.outcome_status = 'pending')::integer,
      count(*) filter (where a.outcome_status = 'reject')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_direct')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_follow_up')::integer,
      count(*) filter (where a.lifecycle_status = 'approved_pending')::integer,
      coalesce(sum(a.duplicate_signal_count), 0)::integer,
      count(distinct a.promotor_id)::integer,
      now()
    from public.vast_applications a
    cross join team_target tt
    where a.sator_id = p_sator_id
      and a.application_date between v_week_start and v_week_end
      and a.deleted_at is null
    group by a.sator_id, tt.target_submissions;
  end if;

  if p_spv_id is not null then
    delete from public.vast_agg_weekly_spv
    where week_start_date = v_week_start and spv_id = p_spv_id;

    insert into public.vast_agg_weekly_spv (
      week_start_date, week_end_date, period_id, spv_id, target_submissions,
      total_submissions, total_acc, total_pending, total_reject, total_closed_direct,
      total_closed_follow_up, total_active_pending, total_duplicate_alerts, promotor_with_input, updated_at
    )
    with team_target as (
      select coalesce(sum(ut.target_vast), 0)::integer as target_submissions
      from public.user_targets ut
      join public.hierarchy_sator_promotor hsp
        on hsp.promotor_id = ut.user_id
       and hsp.active = true
      join public.hierarchy_spv_sator hss
        on hss.sator_id = hsp.sator_id
       and hss.spv_id = p_spv_id
       and hss.active = true
      where ut.period_id = p_period_id
    )
    select
      v_week_start,
      v_week_end,
      max(a.period_id),
      a.spv_id,
      ceil(tt.target_submissions / 4.0)::integer,
      count(*)::integer,
      count(*) filter (where a.outcome_status = 'acc')::integer,
      count(*) filter (where a.outcome_status = 'pending')::integer,
      count(*) filter (where a.outcome_status = 'reject')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_direct')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_follow_up')::integer,
      count(*) filter (where a.lifecycle_status = 'approved_pending')::integer,
      coalesce(sum(a.duplicate_signal_count), 0)::integer,
      count(distinct a.promotor_id)::integer,
      now()
    from public.vast_applications a
    cross join team_target tt
    where a.spv_id = p_spv_id
      and a.application_date between v_week_start and v_week_end
      and a.deleted_at is null
    group by a.spv_id, tt.target_submissions;
  end if;
end;
$$;

create or replace function public.vast_refresh_rollups_after_application()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    perform public.vast_refresh_rollups_for_scope(
      old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.month_key, old.period_id
    );
    perform public.vast_refresh_weekly_rollups_for_scope(
      old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.period_id
    );
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.promotor_id is distinct from new.promotor_id
       or old.sator_id is distinct from new.sator_id
       or old.spv_id is distinct from new.spv_id
       or old.application_date is distinct from new.application_date
       or old.month_key is distinct from new.month_key
       or old.period_id is distinct from new.period_id then
      perform public.vast_refresh_rollups_for_scope(
        old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.month_key, old.period_id
      );
      perform public.vast_refresh_weekly_rollups_for_scope(
        old.promotor_id, old.sator_id, old.spv_id, old.application_date, old.period_id
      );
    end if;
  end if;

  perform public.vast_refresh_rollups_for_scope(
    new.promotor_id, new.sator_id, new.spv_id, new.application_date, new.month_key, new.period_id
  );
  perform public.vast_refresh_weekly_rollups_for_scope(
    new.promotor_id, new.sator_id, new.spv_id, new.application_date, new.period_id
  );
  return new;
end;
$$;

alter table public.vast_agg_weekly_promotor enable row level security;
alter table public.vast_agg_weekly_sator enable row level security;
alter table public.vast_agg_weekly_spv enable row level security;

drop policy if exists "vast agg weekly promotor own" on public.vast_agg_weekly_promotor;
create policy "vast agg weekly promotor own"
on public.vast_agg_weekly_promotor
for select
to authenticated
using (promotor_id = auth.uid() or sator_id = auth.uid() or spv_id = auth.uid());

drop policy if exists "vast agg weekly sator own" on public.vast_agg_weekly_sator;
create policy "vast agg weekly sator own"
on public.vast_agg_weekly_sator
for select
to authenticated
using (sator_id = auth.uid() or exists (
  select 1 from public.hierarchy_spv_sator hss
  where hss.sator_id = vast_agg_weekly_sator.sator_id
    and hss.spv_id = auth.uid()
    and hss.active = true
));

drop policy if exists "vast agg weekly spv own" on public.vast_agg_weekly_spv;
create policy "vast agg weekly spv own"
on public.vast_agg_weekly_spv
for select
to authenticated
using (spv_id = auth.uid());

grant select on public.vast_agg_weekly_promotor to authenticated;
grant select on public.vast_agg_weekly_sator to authenticated;
grant select on public.vast_agg_weekly_spv to authenticated;
grant execute on function public.vast_week_bounds(date) to authenticated;
grant execute on function public.vast_refresh_weekly_rollups_for_scope(uuid, uuid, uuid, date, uuid) to authenticated;
