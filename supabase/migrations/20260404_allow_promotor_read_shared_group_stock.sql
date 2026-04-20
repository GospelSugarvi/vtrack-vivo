drop policy if exists "Promotor can read shared group stock" on public.stok;

create policy "Promotor can read shared group stock"
on public.stok
for select
to public
using (
  exists (
    select 1
    from public.assignments_promotor_store aps
    join public.stores my_store on my_store.id = aps.store_id
    join public.stores stock_store on stock_store.id = stok.store_id
    left join public.store_groups sg on sg.id = my_store.group_id
    where aps.promotor_id = auth.uid()
      and aps.active = true
      and my_store.deleted_at is null
      and stock_store.deleted_at is null
      and sg.deleted_at is null
      and coalesce(sg.stock_handling_mode, '') = 'shared_group'
      and my_store.group_id is not null
      and stock_store.group_id = my_store.group_id
  )
);
