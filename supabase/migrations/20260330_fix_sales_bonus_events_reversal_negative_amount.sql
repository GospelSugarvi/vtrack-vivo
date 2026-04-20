alter table public.sales_bonus_events
  drop constraint if exists sales_bonus_events_bonus_amount_check;

alter table public.sales_bonus_events
  add constraint sales_bonus_events_bonus_amount_check
  check (
    bonus_amount >= 0
    or bonus_type = 'reversal'
  );
