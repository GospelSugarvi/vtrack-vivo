-- Migration: ensure sell in/out can store billions

ALTER TABLE public.user_targets
  ALTER COLUMN target_sell_in TYPE BIGINT USING target_sell_in::bigint,
  ALTER COLUMN target_sell_out TYPE BIGINT USING target_sell_out::bigint;
