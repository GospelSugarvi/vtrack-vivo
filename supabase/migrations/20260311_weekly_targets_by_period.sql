-- Migration: weekly_targets per period

ALTER TABLE public.weekly_targets
  ADD COLUMN IF NOT EXISTS period_id UUID REFERENCES public.target_periods(id);

-- optional index
CREATE INDEX IF NOT EXISTS idx_weekly_targets_period ON public.weekly_targets(period_id, week_number);
