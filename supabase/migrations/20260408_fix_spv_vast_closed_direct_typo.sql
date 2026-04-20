do $$
declare
  fn text;
begin
  select pg_get_functiondef('public.get_spv_vast_page_snapshot(date)'::regprocedure)
    into fn;

  fn := replace(fn, 'am.total_closedDirect', 'am.total_closed_direct');

  execute fn;
end;
$$;
