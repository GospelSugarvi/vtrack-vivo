create table if not exists public.promotor_salary_settings (
  promotor_type text primary key
    check (promotor_type in ('official', 'training')),
  amount numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.update_promotor_salary_settings_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_promotor_salary_settings_updated_at
on public.promotor_salary_settings;

create trigger trg_promotor_salary_settings_updated_at
before update on public.promotor_salary_settings
for each row
execute function public.update_promotor_salary_settings_updated_at();

alter table public.promotor_salary_settings enable row level security;

drop policy if exists "promotor_salary_settings_read_authenticated"
on public.promotor_salary_settings;
create policy "promotor_salary_settings_read_authenticated"
on public.promotor_salary_settings
for select
to authenticated
using (true);

drop policy if exists "promotor_salary_settings_manage_admin"
on public.promotor_salary_settings;
create policy "promotor_salary_settings_manage_admin"
on public.promotor_salary_settings
for all
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'admin'
      and u.deleted_at is null
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'admin'
      and u.deleted_at is null
  )
);

insert into public.promotor_salary_settings (promotor_type, amount)
values
  ('official', 0),
  ('training', 0)
on conflict (promotor_type) do nothing;
