create table if not exists public.system_personas (
  id uuid primary key default gen_random_uuid(),
  persona_code text not null unique,
  display_name text not null,
  linked_user_id uuid not null unique references public.users(id) on delete cascade,
  feature_key text,
  is_active boolean not null default true,
  metadata_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_system_personas_feature_active
  on public.system_personas(feature_key, is_active);

create or replace function public.update_system_personas_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_system_personas_updated_at on public.system_personas;
create trigger trg_system_personas_updated_at
before update on public.system_personas
for each row
execute function public.update_system_personas_updated_at();

alter table public.system_personas enable row level security;

drop policy if exists "system_personas_read_authenticated" on public.system_personas;
create policy "system_personas_read_authenticated"
on public.system_personas
for select
to authenticated
using (true);

drop policy if exists "system_personas_manage_admin" on public.system_personas;
create policy "system_personas_manage_admin"
on public.system_personas
for all
to authenticated
using (public.is_admin_user())
with check (public.is_admin_user());

comment on table public.system_personas is
  'Dedicated non-operational personas for system-generated social/feed interactions.';
