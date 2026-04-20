alter table public.sales_bonus_events
  drop constraint if exists sales_bonus_events_bonus_type_check;

alter table public.sales_bonus_events
  add constraint sales_bonus_events_bonus_type_check
  check (
    bonus_type in ('range', 'flat', 'ratio', 'chip', 'adjustment', 'excluded', 'reversal')
  );
