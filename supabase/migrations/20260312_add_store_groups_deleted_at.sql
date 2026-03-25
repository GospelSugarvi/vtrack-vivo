-- Add deleted_at column for store_groups to support legacy filters.
-- Date: 2026-03-12

ALTER TABLE public.store_groups
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

