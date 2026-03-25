-- Migration: fix weekly_targets uniqueness to be per period

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'weekly_targets_week_number_key'
  ) THEN
    ALTER TABLE public.weekly_targets
      DROP CONSTRAINT weekly_targets_week_number_key;
  END IF;
END $$;

-- Add unique per period
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'weekly_targets_period_week_unique'
  ) THEN
    ALTER TABLE public.weekly_targets
      ADD CONSTRAINT weekly_targets_period_week_unique UNIQUE (period_id, week_number);
  END IF;
END $$;

-- Helpful index
CREATE INDEX IF NOT EXISTS idx_weekly_targets_period_week
  ON public.weekly_targets(period_id, week_number);
