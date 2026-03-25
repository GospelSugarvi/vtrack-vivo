-- Migration: 20260116_update_product_variants.sql
-- Description: Split ram_rom into ram and storage, and add modal (cost price).

-- Add new columns
ALTER TABLE product_variants 
ADD COLUMN IF NOT EXISTS ram text,
ADD COLUMN IF NOT EXISTS storage text,
ADD COLUMN IF NOT EXISTS modal numeric DEFAULT 0 CHECK (modal >= 0);

-- Migrate existing data (attempt to split ram_rom '8/128' -> ram='8', storage='128')
-- This is a best-effort migration for existing data
UPDATE product_variants
SET 
  ram = split_part(ram_rom, '/', 1),
  storage = split_part(ram_rom, '/', 2)
WHERE ram_rom LIKE '%/%';

-- Make columns definition consistent (optional cleanup later)
-- We will stop using 'ram_rom' column in the future code.
