create table if not exists public.ai_feature_settings (
  feature_key text primary key,
  enabled boolean not null default false,
  model_name text not null default 'gemini-2.5-flash',
  system_prompt text not null default '',
  config_json jsonb not null default '{}'::jsonb,
  updated_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_sales_comment_jobs (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales_sell_out(id) on delete cascade,
  feature_key text not null default 'live_feed_sales_comment',
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'skipped')),
  attempt_count integer not null default 0,
  persona_user_id uuid references public.users(id) on delete set null,
  prompt_snapshot text,
  input_context_json jsonb not null default '{}'::jsonb,
  generated_comment text,
  feed_comment_id uuid references public.feed_comments(id) on delete set null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (sale_id)
);

create index if not exists idx_ai_sales_comment_jobs_status_created
  on public.ai_sales_comment_jobs(status, created_at);

create or replace function public.update_ai_feature_settings_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.update_ai_sales_comment_jobs_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_ai_feature_settings_updated_at on public.ai_feature_settings;
create trigger trg_ai_feature_settings_updated_at
before update on public.ai_feature_settings
for each row
execute function public.update_ai_feature_settings_updated_at();

drop trigger if exists trg_ai_sales_comment_jobs_updated_at on public.ai_sales_comment_jobs;
create trigger trg_ai_sales_comment_jobs_updated_at
before update on public.ai_sales_comment_jobs
for each row
execute function public.update_ai_sales_comment_jobs_updated_at();

alter table public.ai_feature_settings enable row level security;
alter table public.ai_sales_comment_jobs enable row level security;

drop policy if exists "ai_feature_settings_read_authenticated" on public.ai_feature_settings;
create policy "ai_feature_settings_read_authenticated"
on public.ai_feature_settings
for select
to authenticated
using (true);

drop policy if exists "ai_feature_settings_manage_admin" on public.ai_feature_settings;
create policy "ai_feature_settings_manage_admin"
on public.ai_feature_settings
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

drop policy if exists "ai_sales_comment_jobs_read_admin" on public.ai_sales_comment_jobs;
create policy "ai_sales_comment_jobs_read_admin"
on public.ai_sales_comment_jobs
for select
to authenticated
using (public.is_admin_user());

drop policy if exists "ai_sales_comment_jobs_manage_admin" on public.ai_sales_comment_jobs;
create policy "ai_sales_comment_jobs_manage_admin"
on public.ai_sales_comment_jobs
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

insert into public.ai_feature_settings (
  feature_key,
  enabled,
  model_name,
  system_prompt,
  config_json
)
values (
  'live_feed_sales_comment',
  false,
  'gemini-2.5-flash',
  trim($prompt$
Kamu adalah rekan tim penjualan yang hangat, suportif, dan natural.
Tugasmu adalah menulis komentar singkat untuk live feed penjualan agar promotor merasa diapresiasi dan tim tetap semangat.

Aturan:
- Jangan pernah menyebut diri sebagai AI, bot, sistem, atau model.
- Tulis seperti manusia biasa di dalam tim.
- Gunakan bahasa Indonesia yang natural, singkat, dan enak dibaca.
- Fokus pada ucapan selamat, apresiasi, dan semangat.
- Hindari terlalu formal, terlalu kaku, terlalu panjang, atau terlalu berlebihan.
- Hindari emoji berlebihan. Maksimal satu emoji jika memang cocok.
- Jangan gunakan tanda kutip.
- Jangan mengulang template yang sama terus-menerus.
- Panjang ideal 1 kalimat pendek atau maksimal 2 kalimat singkat.
- Jangan menyebut informasi yang tidak ada di konteks.

Keluarkan hanya isi komentar akhir, tanpa label tambahan.
$prompt$),
  jsonb_build_object(
    'delay_seconds', 30,
    'persona_user_id', null,
    'language', 'id',
    'max_output_chars', 160,
    'temperature', 0.9
  )
)
on conflict (feature_key) do nothing;

create or replace function public.enqueue_live_feed_ai_sales_comment_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean := false;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if coalesce(new.is_chip_sale, false) then
    return new;
  end if;

  select afs.enabled
    into v_enabled
  from public.ai_feature_settings afs
  where afs.feature_key = 'live_feed_sales_comment'
  limit 1;

  if coalesce(v_enabled, false) = false then
    return new;
  end if;

  insert into public.ai_sales_comment_jobs (
    sale_id,
    feature_key,
    input_context_json
  )
  values (
    new.id,
    'live_feed_sales_comment',
    jsonb_build_object(
      'sale_id', new.id,
      'promotor_id', new.promotor_id,
      'store_id', new.store_id,
      'created_at', new.created_at
    )
  )
  on conflict (sale_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_enqueue_live_feed_ai_sales_comment_job on public.sales_sell_out;
create trigger trg_enqueue_live_feed_ai_sales_comment_job
after insert on public.sales_sell_out
for each row
execute function public.enqueue_live_feed_ai_sales_comment_job();

comment on table public.ai_feature_settings is
  'Database-backed AI feature configuration managed from admin settings.';

comment on table public.ai_sales_comment_jobs is
  'Queue and audit log for auto-generated live feed sales comments.';
