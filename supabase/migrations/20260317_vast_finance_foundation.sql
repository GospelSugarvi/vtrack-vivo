-- Vast Finance foundation schema for Flutter app
-- Scope phase 1: Kupang, roles promotor/sator/spv

create or replace function public.vast_current_date_wita()
returns date
language sql
stable
as $$
  select (now() at time zone 'Asia/Makassar')::date;
$$;

create or replace function public.vast_normalize_text(p_value text)
returns text
language sql
immutable
as $$
  select regexp_replace(lower(trim(coalesce(p_value, ''))), '\s+', ' ', 'g');
$$;

create table if not exists public.vast_applications (
  id uuid primary key default gen_random_uuid(),
  period_id uuid references public.target_periods(id),
  created_by_user_id uuid not null references public.users(id),
  promotor_id uuid not null references public.users(id),
  sator_id uuid references public.users(id),
  spv_id uuid references public.users(id),
  store_id uuid not null references public.stores(id),
  finance_name text not null default 'VAST FINANCE',
  application_date date not null default public.vast_current_date_wita(),
  month_key date not null default date_trunc('month', public.vast_current_date_wita())::date,
  customer_name text not null,
  customer_phone text not null,
  pekerjaan text not null,
  monthly_income numeric default 0 check (monthly_income >= 0),
  has_npwp boolean not null default false,
  product_variant_id uuid references public.product_variants(id),
  product_label text not null,
  limit_amount numeric not null default 0 check (limit_amount >= 0),
  dp_amount numeric not null default 0 check (dp_amount >= 0),
  tenor_months integer not null check (tenor_months > 0),
  outcome_status text not null check (outcome_status in ('acc', 'pending', 'reject')),
  lifecycle_status text not null default 'submitted'
    check (lifecycle_status in (
      'submitted',
      'approved_pending',
      'rejected',
      'closed_direct',
      'closed_follow_up',
      'cancelled'
    )),
  notes text,
  duplicate_signal_count integer not null default 0,
  closing_id uuid,
  deleted_at timestamptz,
  deleted_by_user_id uuid references public.users(id),
  deleted_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vast_application_evidences (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.vast_applications(id) on delete cascade,
  source_stage text not null check (source_stage in ('initial', 'closing')),
  evidence_type text not null check (evidence_type in ('ktp', 'application_proof', 'closing_proof', 'other')),
  file_url text not null,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  sha256_hex text,
  perceptual_hash text,
  created_by_user_id uuid not null references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.vast_closings (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.vast_applications(id) on delete cascade,
  closing_date date not null,
  pickup_date date not null,
  installment_start_date date not null,
  monthly_installment_amount numeric not null default 0 check (monthly_installment_amount >= 0),
  final_dp_amount numeric not null default 0 check (final_dp_amount >= 0),
  final_limit_amount numeric not null default 0 check (final_limit_amount >= 0),
  final_tenor_months integer not null check (final_tenor_months > 0),
  notes text,
  created_by_user_id uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vast_reminders (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.vast_applications(id) on delete cascade,
  closing_id uuid references public.vast_closings(id) on delete cascade,
  promotor_id uuid not null references public.users(id),
  reminder_type text not null check (reminder_type in ('installment_followup', 'tenor_completion_followup')),
  scheduled_date date not null,
  status text not null default 'pending' check (status in ('pending', 'done', 'dismissed')),
  reminder_title text not null,
  reminder_body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (application_id, reminder_type, scheduled_date)
);

create table if not exists public.vast_fraud_signals (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.vast_applications(id) on delete cascade,
  matched_application_id uuid references public.vast_applications(id) on delete cascade,
  signal_type text not null check (signal_type in ('exact_file_match', 'perceptual_match', 'metadata_match', 'hybrid_match')),
  severity text not null check (severity in ('low', 'medium', 'high')),
  status text not null default 'open' check (status in ('open', 'reviewed_valid', 'dismissed')),
  summary text not null,
  detection_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (application_id, matched_application_id, signal_type)
);

create table if not exists public.vast_fraud_signal_items (
  id uuid primary key default gen_random_uuid(),
  signal_id uuid not null references public.vast_fraud_signals(id) on delete cascade,
  current_evidence_id uuid references public.vast_application_evidences(id) on delete cascade,
  matched_evidence_id uuid references public.vast_application_evidences(id) on delete cascade,
  match_type text not null check (match_type in ('exact_hash', 'perceptual_hash', 'metadata')),
  confidence_score numeric not null default 1 check (confidence_score >= 0 and confidence_score <= 1),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.vast_alerts (
  id uuid primary key default gen_random_uuid(),
  signal_id uuid not null references public.vast_fraud_signals(id) on delete cascade,
  application_id uuid not null references public.vast_applications(id) on delete cascade,
  recipient_user_id uuid not null references public.users(id),
  recipient_role text not null check (recipient_role in ('sator', 'spv')),
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (signal_id, recipient_user_id)
);

create table if not exists public.vast_agg_daily_promotor (
  metric_date date not null,
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
  primary key (metric_date, promotor_id)
);

create table if not exists public.vast_agg_monthly_promotor (
  month_key date not null,
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
  achievement_pct numeric not null default 0,
  time_gone_pct numeric not null default 0,
  underperform boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (month_key, promotor_id)
);

create table if not exists public.vast_agg_daily_sator (
  metric_date date not null,
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
  primary key (metric_date, sator_id)
);

create table if not exists public.vast_agg_monthly_sator (
  month_key date not null,
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
  achievement_pct numeric not null default 0,
  time_gone_pct numeric not null default 0,
  underperform boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (month_key, sator_id)
);

create table if not exists public.vast_agg_daily_spv (
  metric_date date not null,
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
  primary key (metric_date, spv_id)
);

create table if not exists public.vast_agg_monthly_spv (
  month_key date not null,
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
  achievement_pct numeric not null default 0,
  time_gone_pct numeric not null default 0,
  underperform boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (month_key, spv_id)
);

alter table public.vast_applications
  add constraint vast_applications_closing_id_fkey
  foreign key (closing_id) references public.vast_closings(id);

create index if not exists idx_vast_applications_promotor_date on public.vast_applications(promotor_id, application_date) where deleted_at is null;
create index if not exists idx_vast_applications_sator_date on public.vast_applications(sator_id, application_date) where deleted_at is null;
create index if not exists idx_vast_applications_spv_date on public.vast_applications(spv_id, application_date) where deleted_at is null;
create index if not exists idx_vast_applications_month on public.vast_applications(month_key, promotor_id) where deleted_at is null;
create index if not exists idx_vast_applications_phone on public.vast_applications(customer_phone) where deleted_at is null;
create index if not exists idx_vast_evidences_sha on public.vast_application_evidences(sha256_hex) where sha256_hex is not null;
create index if not exists idx_vast_evidences_phash on public.vast_application_evidences(perceptual_hash) where perceptual_hash is not null;
create index if not exists idx_vast_reminders_promotor_date on public.vast_reminders(promotor_id, scheduled_date, status);
create index if not exists idx_vast_alerts_recipient_date on public.vast_alerts(recipient_user_id, created_at desc);

create or replace function public.vast_time_gone_pct(p_month_key date)
returns numeric
language plpgsql
stable
as $$
declare
  v_today date := public.vast_current_date_wita();
  v_days_in_month integer;
  v_elapsed integer;
begin
  if p_month_key is null then
    return 0;
  end if;

  if p_month_key > date_trunc('month', v_today)::date then
    return 0;
  end if;

  if p_month_key < date_trunc('month', v_today)::date then
    return 100;
  end if;

  v_days_in_month := extract(day from (date_trunc('month', p_month_key) + interval '1 month - 1 day'));
  v_elapsed := extract(day from v_today);
  return round((v_elapsed::numeric / greatest(v_days_in_month, 1)::numeric) * 100, 2);
end;
$$;

create or replace function public.vast_assign_application_defaults()
returns trigger
language plpgsql
as $$
declare
  v_promotor_id uuid;
  v_store_id uuid;
begin
  if new.created_by_user_id is null then
    new.created_by_user_id := auth.uid();
  end if;

  if new.promotor_id is null then
    new.promotor_id := new.created_by_user_id;
  end if;

  v_promotor_id := new.promotor_id;

  if new.store_id is null then
    select aps.store_id
      into v_store_id
    from public.assignments_promotor_store aps
    where aps.promotor_id = v_promotor_id
      and aps.active = true
    order by aps.created_at desc
    limit 1;

    new.store_id := v_store_id;
  end if;

  if new.period_id is null then
    new.period_id := public.get_current_target_period();
  end if;

  if new.application_date is null then
    new.application_date := public.vast_current_date_wita();
  end if;

  new.month_key := date_trunc('month', new.application_date)::date;
  new.finance_name := 'VAST FINANCE';

  if new.sator_id is null then
    select hsp.sator_id
      into new.sator_id
    from public.hierarchy_sator_promotor hsp
    where hsp.promotor_id = v_promotor_id
      and hsp.active = true
    order by hsp.created_at desc
    limit 1;
  end if;

  if new.spv_id is null and new.sator_id is not null then
    select hss.spv_id
      into new.spv_id
    from public.hierarchy_spv_sator hss
    where hss.sator_id = new.sator_id
      and hss.active = true
    order by hss.created_at desc
    limit 1;
  end if;

  if new.lifecycle_status = 'submitted' or new.lifecycle_status is null then
    new.lifecycle_status := case
      when new.outcome_status = 'acc' then 'closed_direct'
      when new.outcome_status = 'pending' then 'approved_pending'
      when new.outcome_status = 'reject' then 'rejected'
      else 'submitted'
    end;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.vast_refresh_rollups_for_scope(
  p_promotor_id uuid,
  p_sator_id uuid,
  p_spv_id uuid,
  p_metric_date date,
  p_month_key date,
  p_period_id uuid
)
returns void
language plpgsql
as $$
declare
  v_target integer := 0;
  v_time_gone numeric := public.vast_time_gone_pct(p_month_key);
begin
  if p_promotor_id is not null and p_metric_date is not null then
    delete from public.vast_agg_daily_promotor
    where metric_date = p_metric_date and promotor_id = p_promotor_id;

    insert into public.vast_agg_daily_promotor (
      metric_date, period_id, promotor_id, store_id, sator_id, spv_id,
      target_submissions, total_submissions, total_acc, total_pending, total_reject,
      total_closed_direct, total_closed_follow_up, total_active_pending, total_duplicate_alerts, updated_at
    )
    select
      p_metric_date,
      max(a.period_id),
      a.promotor_id,
      max(a.store_id),
      max(a.sator_id),
      max(a.spv_id),
      coalesce(max(ut.target_vast), 0),
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
    left join public.user_targets ut
      on ut.user_id = a.promotor_id and ut.period_id = a.period_id
    where a.promotor_id = p_promotor_id
      and a.application_date = p_metric_date
      and a.deleted_at is null
    group by a.promotor_id;
  end if;

  if p_promotor_id is not null and p_month_key is not null then
    select coalesce(max(target_vast), 0)
      into v_target
    from public.user_targets
    where user_id = p_promotor_id
      and period_id = p_period_id;

    delete from public.vast_agg_monthly_promotor
    where month_key = p_month_key and promotor_id = p_promotor_id;

    insert into public.vast_agg_monthly_promotor (
      month_key, period_id, promotor_id, store_id, sator_id, spv_id, target_submissions,
      total_submissions, total_acc, total_pending, total_reject, total_closed_direct,
      total_closed_follow_up, total_active_pending, total_duplicate_alerts,
      achievement_pct, time_gone_pct, underperform, updated_at
    )
    select
      p_month_key,
      max(a.period_id),
      a.promotor_id,
      max(a.store_id),
      max(a.sator_id),
      max(a.spv_id),
      v_target,
      count(*)::integer,
      count(*) filter (where a.outcome_status = 'acc')::integer,
      count(*) filter (where a.outcome_status = 'pending')::integer,
      count(*) filter (where a.outcome_status = 'reject')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_direct')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_follow_up')::integer,
      count(*) filter (where a.lifecycle_status = 'approved_pending')::integer,
      coalesce(sum(a.duplicate_signal_count), 0)::integer,
      case when v_target > 0 then round((count(*)::numeric / v_target::numeric) * 100, 2) else 0 end,
      v_time_gone,
      case when v_target > 0 then ((count(*)::numeric / v_target::numeric) * 100) < v_time_gone else false end,
      now()
    from public.vast_applications a
    where a.promotor_id = p_promotor_id
      and a.month_key = p_month_key
      and a.deleted_at is null
    group by a.promotor_id;
  end if;

  if p_sator_id is not null and p_metric_date is not null then
    delete from public.vast_agg_daily_sator
    where metric_date = p_metric_date and sator_id = p_sator_id;

    insert into public.vast_agg_daily_sator (
      metric_date, period_id, sator_id, target_submissions, total_submissions, total_acc,
      total_pending, total_reject, total_closed_direct, total_closed_follow_up,
      total_active_pending, total_duplicate_alerts, promotor_with_input, updated_at
    )
    select
      p_metric_date,
      max(a.period_id),
      a.sator_id,
      coalesce(sum(distinct ut.target_vast), 0)::integer,
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
    left join public.user_targets ut
      on ut.user_id = a.promotor_id and ut.period_id = a.period_id
    where a.sator_id = p_sator_id
      and a.application_date = p_metric_date
      and a.deleted_at is null
    group by a.sator_id;
  end if;

  if p_sator_id is not null and p_month_key is not null then
    delete from public.vast_agg_monthly_sator
    where month_key = p_month_key and sator_id = p_sator_id;

    insert into public.vast_agg_monthly_sator (
      month_key, period_id, sator_id, target_submissions, total_submissions, total_acc,
      total_pending, total_reject, total_closed_direct, total_closed_follow_up,
      total_active_pending, total_duplicate_alerts, achievement_pct, time_gone_pct,
      underperform, updated_at
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
      p_month_key,
      max(a.period_id),
      a.sator_id,
      tt.target_submissions,
      count(*)::integer,
      count(*) filter (where a.outcome_status = 'acc')::integer,
      count(*) filter (where a.outcome_status = 'pending')::integer,
      count(*) filter (where a.outcome_status = 'reject')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_direct')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_follow_up')::integer,
      count(*) filter (where a.lifecycle_status = 'approved_pending')::integer,
      coalesce(sum(a.duplicate_signal_count), 0)::integer,
      case when tt.target_submissions > 0 then round((count(*)::numeric / tt.target_submissions::numeric) * 100, 2) else 0 end,
      v_time_gone,
      case when tt.target_submissions > 0 then ((count(*)::numeric / tt.target_submissions::numeric) * 100) < v_time_gone else false end,
      now()
    from public.vast_applications a
    cross join team_target tt
    where a.sator_id = p_sator_id
      and a.month_key = p_month_key
      and a.deleted_at is null
    group by a.sator_id, tt.target_submissions;
  end if;

  if p_spv_id is not null and p_metric_date is not null then
    delete from public.vast_agg_daily_spv
    where metric_date = p_metric_date and spv_id = p_spv_id;

    insert into public.vast_agg_daily_spv (
      metric_date, period_id, spv_id, target_submissions, total_submissions, total_acc,
      total_pending, total_reject, total_closed_direct, total_closed_follow_up,
      total_active_pending, total_duplicate_alerts, promotor_with_input, updated_at
    )
    select
      p_metric_date,
      max(a.period_id),
      a.spv_id,
      coalesce(sum(distinct ut.target_vast), 0)::integer,
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
    left join public.user_targets ut
      on ut.user_id = a.promotor_id and ut.period_id = a.period_id
    where a.spv_id = p_spv_id
      and a.application_date = p_metric_date
      and a.deleted_at is null
    group by a.spv_id;
  end if;

  if p_spv_id is not null and p_month_key is not null then
    delete from public.vast_agg_monthly_spv
    where month_key = p_month_key and spv_id = p_spv_id;

    insert into public.vast_agg_monthly_spv (
      month_key, period_id, spv_id, target_submissions, total_submissions, total_acc,
      total_pending, total_reject, total_closed_direct, total_closed_follow_up,
      total_active_pending, total_duplicate_alerts, achievement_pct, time_gone_pct,
      underperform, updated_at
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
      p_month_key,
      max(a.period_id),
      a.spv_id,
      tt.target_submissions,
      count(*)::integer,
      count(*) filter (where a.outcome_status = 'acc')::integer,
      count(*) filter (where a.outcome_status = 'pending')::integer,
      count(*) filter (where a.outcome_status = 'reject')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_direct')::integer,
      count(*) filter (where a.lifecycle_status = 'closed_follow_up')::integer,
      count(*) filter (where a.lifecycle_status = 'approved_pending')::integer,
      coalesce(sum(a.duplicate_signal_count), 0)::integer,
      case when tt.target_submissions > 0 then round((count(*)::numeric / tt.target_submissions::numeric) * 100, 2) else 0 end,
      v_time_gone,
      case when tt.target_submissions > 0 then ((count(*)::numeric / tt.target_submissions::numeric) * 100) < v_time_gone else false end,
      now()
    from public.vast_applications a
    cross join team_target tt
    where a.spv_id = p_spv_id
      and a.month_key = p_month_key
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
    end if;
  end if;

  perform public.vast_refresh_rollups_for_scope(
    new.promotor_id, new.sator_id, new.spv_id, new.application_date, new.month_key, new.period_id
  );
  return new;
end;
$$;

create or replace function public.vast_generate_reminders_for_closing(p_closing_id uuid)
returns void
language plpgsql
as $$
declare
  v_closing record;
  v_promotor_id uuid;
  i integer;
  v_schedule_date date;
begin
  select vc.*, va.promotor_id, va.customer_name
    into v_closing
  from public.vast_closings vc
  join public.vast_applications va on va.id = vc.application_id
  where vc.id = p_closing_id;

  if not found then
    return;
  end if;

  v_promotor_id := v_closing.promotor_id;

  delete from public.vast_reminders where closing_id = p_closing_id;

  for i in 0..(v_closing.final_tenor_months - 1) loop
    v_schedule_date := (v_closing.installment_start_date + make_interval(months => i))::date;
    insert into public.vast_reminders (
      application_id, closing_id, promotor_id, reminder_type, scheduled_date,
      reminder_title, reminder_body
    ) values (
      v_closing.application_id,
      p_closing_id,
      v_promotor_id,
      'installment_followup',
      v_schedule_date,
      'Reminder cicilan nasabah',
      'Follow-up cicilan bulanan untuk ' || coalesce(v_closing.customer_name, 'nasabah') || '.'
    )
    on conflict (application_id, reminder_type, scheduled_date) do nothing;
  end loop;

  insert into public.vast_reminders (
    application_id, closing_id, promotor_id, reminder_type, scheduled_date,
    reminder_title, reminder_body
  ) values (
    v_closing.application_id,
    p_closing_id,
    v_promotor_id,
    'tenor_completion_followup',
    (v_closing.installment_start_date + make_interval(months => v_closing.final_tenor_months))::date,
    'Reminder follow-up repeat order',
    'Masa cicilan nasabah ' || coalesce(v_closing.customer_name, 'ini') || ' selesai. Tindak lanjuti peluang pengajuan baru.'
  )
  on conflict (application_id, reminder_type, scheduled_date) do nothing;
end;
$$;

create or replace function public.vast_apply_closing()
returns trigger
language plpgsql
as $$
begin
  new.pickup_date := coalesce(new.pickup_date, new.closing_date);
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.vast_after_closing_upsert()
returns trigger
language plpgsql
as $$
begin
  update public.vast_applications
  set
    lifecycle_status = 'closed_follow_up',
    closing_id = new.id,
    updated_at = now()
  where id = new.application_id
    and deleted_at is null;

  perform public.vast_generate_reminders_for_closing(new.id);
  return new;
end;
$$;

create or replace function public.vast_create_alerts_for_signal(p_signal_id uuid)
returns void
language plpgsql
as $$
declare
  v_signal record;
begin
  select fs.*, va.sator_id, va.spv_id, va.customer_name, va.application_date
    into v_signal
  from public.vast_fraud_signals fs
  join public.vast_applications va on va.id = fs.application_id
  where fs.id = p_signal_id;

  if not found then
    return;
  end if;

  if v_signal.sator_id is not null then
    insert into public.vast_alerts (
      signal_id, application_id, recipient_user_id, recipient_role, title, body
    ) values (
      v_signal.id,
      v_signal.application_id,
      v_signal.sator_id,
      'sator',
      'Indikasi duplikasi bukti VAST',
      v_signal.summary
    )
    on conflict (signal_id, recipient_user_id) do nothing;
  end if;

  if v_signal.spv_id is not null then
    insert into public.vast_alerts (
      signal_id, application_id, recipient_user_id, recipient_role, title, body
    ) values (
      v_signal.id,
      v_signal.application_id,
      v_signal.spv_id,
      'spv',
      'Indikasi duplikasi bukti VAST',
      v_signal.summary
    )
    on conflict (signal_id, recipient_user_id) do nothing;
  end if;
end;
$$;

create or replace function public.vast_refresh_duplicate_count(p_application_id uuid)
returns void
language plpgsql
as $$
begin
  update public.vast_applications
  set
    duplicate_signal_count = (
      select count(*)::integer
      from public.vast_fraud_signals
      where application_id = p_application_id
        and status = 'open'
    ),
    updated_at = now()
  where id = p_application_id;
end;
$$;

create or replace function public.vast_detect_application_metadata_signals(p_application_id uuid)
returns void
language plpgsql
as $$
declare
  v_app record;
  v_other record;
  v_signal_id uuid;
begin
  select *
    into v_app
  from public.vast_applications
  where id = p_application_id
    and deleted_at is null;

  if not found then
    return;
  end if;

  for v_other in
    select other.id, other.application_date, other.customer_name, other.customer_phone
    from public.vast_applications other
    where other.id <> v_app.id
      and other.deleted_at is null
      and (
        (
          public.vast_normalize_text(other.customer_phone) = public.vast_normalize_text(v_app.customer_phone)
          and public.vast_normalize_text(other.customer_name) = public.vast_normalize_text(v_app.customer_name)
        )
        or (
          public.vast_normalize_text(other.customer_name) = public.vast_normalize_text(v_app.customer_name)
          and other.tenor_months = v_app.tenor_months
          and other.limit_amount = v_app.limit_amount
        )
      )
  loop
    insert into public.vast_fraud_signals (
      application_id, matched_application_id, signal_type, severity, summary, detection_payload
    ) values (
      v_app.id,
      v_other.id,
      'metadata_match',
      'medium',
      'Data mirip terdeteksi. Pengajuan lama pada ' || to_char(v_other.application_date, 'DD Mon YYYY') ||
      ' dan input baru pada ' || to_char(v_app.application_date, 'DD Mon YYYY') || '.',
      jsonb_build_object(
        'old_application_date', v_other.application_date,
        'new_application_date', v_app.application_date,
        'old_customer_name', v_other.customer_name,
        'new_customer_name', v_app.customer_name,
        'old_customer_phone', v_other.customer_phone,
        'new_customer_phone', v_app.customer_phone
      )
    )
    on conflict (application_id, matched_application_id, signal_type)
    do update set
      detection_payload = excluded.detection_payload,
      updated_at = now()
    returning id into v_signal_id;

    if v_signal_id is not null then
      insert into public.vast_fraud_signal_items (
        signal_id, match_type, confidence_score, details
      ) values (
        v_signal_id,
        'metadata',
        0.80,
        jsonb_build_object(
          'matched_application_id', v_other.id,
          'old_application_date', v_other.application_date,
          'new_application_date', v_app.application_date
        )
      );

      perform public.vast_create_alerts_for_signal(v_signal_id);
    end if;
  end loop;

  perform public.vast_refresh_duplicate_count(v_app.id);
end;
$$;

create or replace function public.vast_detect_evidence_signals(p_application_id uuid)
returns void
language plpgsql
as $$
declare
  v_match record;
  v_signal_id uuid;
begin
  for v_match in
    select
      current_ev.id as current_evidence_id,
      matched_ev.id as matched_evidence_id,
      matched_app.id as matched_application_id,
      current_ev.sha256_hex,
      current_ev.perceptual_hash,
      matched_app.application_date as matched_application_date,
      current_app.application_date as current_application_date,
      case
        when current_ev.sha256_hex is not null and current_ev.sha256_hex = matched_ev.sha256_hex then 'exact_file_match'
        when current_ev.perceptual_hash is not null and current_ev.perceptual_hash = matched_ev.perceptual_hash then 'perceptual_match'
      end as signal_type
    from public.vast_application_evidences current_ev
    join public.vast_applications current_app on current_app.id = current_ev.application_id
    join public.vast_application_evidences matched_ev
      on matched_ev.id <> current_ev.id
     and (
       (current_ev.sha256_hex is not null and current_ev.sha256_hex = matched_ev.sha256_hex)
       or (current_ev.perceptual_hash is not null and current_ev.perceptual_hash = matched_ev.perceptual_hash)
     )
    join public.vast_applications matched_app on matched_app.id = matched_ev.application_id
    where current_ev.application_id = p_application_id
      and matched_app.id <> current_app.id
      and matched_app.deleted_at is null
  loop
    insert into public.vast_fraud_signals (
      application_id, matched_application_id, signal_type, severity, summary, detection_payload
    ) values (
      p_application_id,
      v_match.matched_application_id,
      v_match.signal_type,
      case when v_match.signal_type = 'exact_file_match' then 'high' else 'medium' end,
      'Bukti foto pernah dikirim pada ' || to_char(v_match.matched_application_date, 'DD Mon YYYY') ||
      ' dan dipakai lagi pada ' || to_char(v_match.current_application_date, 'DD Mon YYYY') || '.',
      jsonb_build_object(
        'old_application_date', v_match.matched_application_date,
        'new_application_date', v_match.current_application_date,
        'matched_application_id', v_match.matched_application_id,
        'signal_type', v_match.signal_type
      )
    )
    on conflict (application_id, matched_application_id, signal_type)
    do update set
      detection_payload = excluded.detection_payload,
      updated_at = now()
    returning id into v_signal_id;

    if v_signal_id is not null then
      insert into public.vast_fraud_signal_items (
        signal_id, current_evidence_id, matched_evidence_id, match_type, confidence_score, details
      ) values (
        v_signal_id,
        v_match.current_evidence_id,
        v_match.matched_evidence_id,
        case when v_match.signal_type = 'exact_file_match' then 'exact_hash' else 'perceptual_hash' end,
        case when v_match.signal_type = 'exact_file_match' then 1 else 0.92 end,
        jsonb_build_object(
          'old_application_date', v_match.matched_application_date,
          'new_application_date', v_match.current_application_date
        )
      );

      perform public.vast_create_alerts_for_signal(v_signal_id);
    end if;
  end loop;

  perform public.vast_refresh_duplicate_count(p_application_id);
end;
$$;

create or replace function public.vast_after_evidence_upsert()
returns trigger
language plpgsql
as $$
begin
  perform public.vast_detect_evidence_signals(new.application_id);
  return new;
end;
$$;

create or replace function public.vast_after_application_upsert()
returns trigger
language plpgsql
as $$
begin
  perform public.vast_detect_application_metadata_signals(new.id);
  return new;
end;
$$;

drop trigger if exists vast_assign_application_defaults on public.vast_applications;
create trigger vast_assign_application_defaults
before insert or update on public.vast_applications
for each row execute function public.vast_assign_application_defaults();

drop trigger if exists vast_refresh_rollups_after_application on public.vast_applications;
create trigger vast_refresh_rollups_after_application
after insert or update or delete on public.vast_applications
for each row execute function public.vast_refresh_rollups_after_application();

drop trigger if exists vast_after_application_upsert on public.vast_applications;
create trigger vast_after_application_upsert
after insert or update on public.vast_applications
for each row execute function public.vast_after_application_upsert();

drop trigger if exists vast_apply_closing on public.vast_closings;
create trigger vast_apply_closing
before insert or update on public.vast_closings
for each row execute function public.vast_apply_closing();

drop trigger if exists vast_after_closing_upsert on public.vast_closings;
create trigger vast_after_closing_upsert
after insert or update on public.vast_closings
for each row execute function public.vast_after_closing_upsert();

drop trigger if exists vast_after_evidence_upsert on public.vast_application_evidences;
create trigger vast_after_evidence_upsert
after insert or update on public.vast_application_evidences
for each row execute function public.vast_after_evidence_upsert();

alter table public.vast_applications enable row level security;
alter table public.vast_application_evidences enable row level security;
alter table public.vast_closings enable row level security;
alter table public.vast_reminders enable row level security;
alter table public.vast_fraud_signals enable row level security;
alter table public.vast_fraud_signal_items enable row level security;
alter table public.vast_alerts enable row level security;
alter table public.vast_agg_daily_promotor enable row level security;
alter table public.vast_agg_monthly_promotor enable row level security;
alter table public.vast_agg_daily_sator enable row level security;
alter table public.vast_agg_monthly_sator enable row level security;
alter table public.vast_agg_daily_spv enable row level security;
alter table public.vast_agg_monthly_spv enable row level security;

drop policy if exists "vast applications promotor own" on public.vast_applications;
create policy "vast applications promotor own"
on public.vast_applications
for all
to authenticated
using (promotor_id = auth.uid())
with check (promotor_id = auth.uid());

drop policy if exists "vast applications team leaders" on public.vast_applications;
create policy "vast applications team leaders"
on public.vast_applications
for select
to authenticated
using (sator_id = auth.uid() or spv_id = auth.uid());

drop policy if exists "vast applications team leaders update" on public.vast_applications;
create policy "vast applications team leaders update"
on public.vast_applications
for update
to authenticated
using (sator_id = auth.uid() or spv_id = auth.uid())
with check (sator_id = auth.uid() or spv_id = auth.uid());

drop policy if exists "vast evidences own and team" on public.vast_application_evidences;
create policy "vast evidences own and team"
on public.vast_application_evidences
for select
to authenticated
using (
  exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and (va.promotor_id = auth.uid() or va.sator_id = auth.uid() or va.spv_id = auth.uid())
  )
);

drop policy if exists "vast evidences own insert" on public.vast_application_evidences;
create policy "vast evidences own insert"
on public.vast_application_evidences
for insert
to authenticated
with check (
  created_by_user_id = auth.uid()
  and exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and va.promotor_id = auth.uid()
  )
);

drop policy if exists "vast closings own and team" on public.vast_closings;
create policy "vast closings own and team"
on public.vast_closings
for select
to authenticated
using (
  exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and (va.promotor_id = auth.uid() or va.sator_id = auth.uid() or va.spv_id = auth.uid())
  )
);

drop policy if exists "vast closings own insert" on public.vast_closings;
create policy "vast closings own insert"
on public.vast_closings
for insert
to authenticated
with check (
  created_by_user_id = auth.uid()
  and exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and va.promotor_id = auth.uid()
      and va.lifecycle_status = 'approved_pending'
  )
);

drop policy if exists "vast reminders promotor own" on public.vast_reminders;
create policy "vast reminders promotor own"
on public.vast_reminders
for select
to authenticated
using (promotor_id = auth.uid());

drop policy if exists "vast reminders promotor update" on public.vast_reminders;
create policy "vast reminders promotor update"
on public.vast_reminders
for update
to authenticated
using (promotor_id = auth.uid())
with check (promotor_id = auth.uid());

drop policy if exists "vast fraud signals leaders" on public.vast_fraud_signals;
create policy "vast fraud signals leaders"
on public.vast_fraud_signals
for select
to authenticated
using (
  exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and (va.sator_id = auth.uid() or va.spv_id = auth.uid())
  )
);

drop policy if exists "vast fraud signals leaders update" on public.vast_fraud_signals;
create policy "vast fraud signals leaders update"
on public.vast_fraud_signals
for update
to authenticated
using (
  exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and (va.sator_id = auth.uid() or va.spv_id = auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.vast_applications va
    where va.id = application_id
      and (va.sator_id = auth.uid() or va.spv_id = auth.uid())
  )
);

drop policy if exists "vast fraud signal items leaders" on public.vast_fraud_signal_items;
create policy "vast fraud signal items leaders"
on public.vast_fraud_signal_items
for select
to authenticated
using (
  exists (
    select 1
    from public.vast_fraud_signals fs
    join public.vast_applications va on va.id = fs.application_id
    where fs.id = signal_id
      and (va.sator_id = auth.uid() or va.spv_id = auth.uid())
  )
);

drop policy if exists "vast alerts recipient" on public.vast_alerts;
create policy "vast alerts recipient"
on public.vast_alerts
for select
to authenticated
using (recipient_user_id = auth.uid());

drop policy if exists "vast alerts recipient update" on public.vast_alerts;
create policy "vast alerts recipient update"
on public.vast_alerts
for update
to authenticated
using (recipient_user_id = auth.uid())
with check (recipient_user_id = auth.uid());

drop policy if exists "vast agg daily promotor own" on public.vast_agg_daily_promotor;
create policy "vast agg daily promotor own"
on public.vast_agg_daily_promotor
for select
to authenticated
using (promotor_id = auth.uid() or sator_id = auth.uid() or spv_id = auth.uid());

drop policy if exists "vast agg monthly promotor own" on public.vast_agg_monthly_promotor;
create policy "vast agg monthly promotor own"
on public.vast_agg_monthly_promotor
for select
to authenticated
using (promotor_id = auth.uid() or sator_id = auth.uid() or spv_id = auth.uid());

drop policy if exists "vast agg daily sator own" on public.vast_agg_daily_sator;
create policy "vast agg daily sator own"
on public.vast_agg_daily_sator
for select
to authenticated
using (sator_id = auth.uid() or exists (
  select 1 from public.hierarchy_spv_sator hss
  where hss.sator_id = vast_agg_daily_sator.sator_id
    and hss.spv_id = auth.uid()
    and hss.active = true
));

drop policy if exists "vast agg monthly sator own" on public.vast_agg_monthly_sator;
create policy "vast agg monthly sator own"
on public.vast_agg_monthly_sator
for select
to authenticated
using (sator_id = auth.uid() or exists (
  select 1 from public.hierarchy_spv_sator hss
  where hss.sator_id = vast_agg_monthly_sator.sator_id
    and hss.spv_id = auth.uid()
    and hss.active = true
));

drop policy if exists "vast agg daily spv own" on public.vast_agg_daily_spv;
create policy "vast agg daily spv own"
on public.vast_agg_daily_spv
for select
to authenticated
using (spv_id = auth.uid());

drop policy if exists "vast agg monthly spv own" on public.vast_agg_monthly_spv;
create policy "vast agg monthly spv own"
on public.vast_agg_monthly_spv
for select
to authenticated
using (spv_id = auth.uid());

grant select, insert, update on public.vast_applications to authenticated;
grant select, insert, update on public.vast_application_evidences to authenticated;
grant select, insert, update on public.vast_closings to authenticated;
grant select, update on public.vast_reminders to authenticated;
grant select, update on public.vast_fraud_signals to authenticated;
grant select on public.vast_fraud_signal_items to authenticated;
grant select, update on public.vast_alerts to authenticated;
grant select on public.vast_agg_daily_promotor to authenticated;
grant select on public.vast_agg_monthly_promotor to authenticated;
grant select on public.vast_agg_daily_sator to authenticated;
grant select on public.vast_agg_monthly_sator to authenticated;
grant select on public.vast_agg_daily_spv to authenticated;
grant select on public.vast_agg_monthly_spv to authenticated;

grant execute on function public.vast_current_date_wita() to authenticated;
grant execute on function public.vast_time_gone_pct(date) to authenticated;
grant execute on function public.vast_generate_reminders_for_closing(uuid) to authenticated;
grant execute on function public.vast_detect_application_metadata_signals(uuid) to authenticated;
grant execute on function public.vast_detect_evidence_signals(uuid) to authenticated;
