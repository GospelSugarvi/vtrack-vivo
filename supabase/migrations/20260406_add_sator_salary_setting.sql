alter table public.promotor_salary_settings
drop constraint if exists promotor_salary_settings_promotor_type_check;

alter table public.promotor_salary_settings
add constraint promotor_salary_settings_promotor_type_check
check (promotor_type in ('official', 'training', 'sator'));

insert into public.promotor_salary_settings (promotor_type, amount)
values ('sator', 0)
on conflict (promotor_type) do nothing;
