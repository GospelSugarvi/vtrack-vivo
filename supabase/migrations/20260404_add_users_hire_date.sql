alter table public.users
add column if not exists hire_date date;

comment on column public.users.hire_date is 'Tanggal masuk / hire date user';
