-- Migration: 20260311_add_target_special_mode.sql
-- Store special target mode: 'detail' or 'total'

ALTER TABLE public.user_targets
ADD COLUMN IF NOT EXISTS target_special_mode TEXT DEFAULT 'detail';
