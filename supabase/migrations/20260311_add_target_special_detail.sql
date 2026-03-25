-- Migration: 20260311_add_target_special_detail.sql
-- Store per-product special target detail

ALTER TABLE public.user_targets
ADD COLUMN IF NOT EXISTS target_special_detail JSONB DEFAULT '{}';
