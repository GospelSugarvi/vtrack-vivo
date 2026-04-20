insert into storage.buckets (id, name, public)
select 'photos', 'photos', true
where not exists (
  select 1
  from storage.buckets
  where id = 'photos'
);
