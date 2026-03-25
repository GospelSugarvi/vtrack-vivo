-- Add data_source to bonus tables for flexible source configuration

-- 1. Point Ranges (Sator/SPV Bonus Poin)
ALTER TABLE point_ranges ADD COLUMN IF NOT EXISTS data_source text DEFAULT 'sell_out' CHECK (data_source IN ('sell_out', 'sell_in'));

-- 2. Special Rewards (Sator/SPV Reward Khusus)
ALTER TABLE special_rewards ADD COLUMN IF NOT EXISTS data_source text DEFAULT 'sell_out' CHECK (data_source IN ('sell_out', 'sell_in'));

-- Note:
-- sell_out = dari sales_data (jualan promotor ke customer)
-- sell_in = dari orders/vast_finance_data (orderan ke warehouse)
-- Default: sell_out (current behavior)
-- Admin bisa ubah per-rule sesuai kebutuhan
