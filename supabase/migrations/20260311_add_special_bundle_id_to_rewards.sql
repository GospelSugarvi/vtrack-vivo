-- Migration: 20260311_add_special_bundle_id_to_rewards.sql
-- Link special_rewards to special_focus_bundles

ALTER TABLE public.special_rewards
ADD COLUMN IF NOT EXISTS special_bundle_id uuid REFERENCES special_focus_bundles(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_special_rewards_special_bundle
  ON public.special_rewards(special_bundle_id);
