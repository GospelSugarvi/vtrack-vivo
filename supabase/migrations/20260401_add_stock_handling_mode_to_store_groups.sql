alter table public.store_groups
add column if not exists stock_handling_mode text not null default 'distributed_group';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'store_groups_stock_handling_mode_check'
      and conrelid = 'public.store_groups'::regclass
  ) then
    alter table public.store_groups
    add constraint store_groups_stock_handling_mode_check
    check (stock_handling_mode in ('shared_group', 'distributed_group'));
  end if;
end;
$$;

comment on column public.store_groups.stock_handling_mode is
'Defines how warehouse/imported stock should be handled for this group. shared_group keeps one shared pool, distributed_group allocates stock to branch stores.';
