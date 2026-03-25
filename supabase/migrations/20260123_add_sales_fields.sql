-- Add notes field to sales_sell_out table
-- For leaderboard live feed display
-- Note: customer_type already exists

ALTER TABLE sales_sell_out
ADD COLUMN IF NOT EXISTS notes TEXT;

-- Add comment
COMMENT ON COLUMN sales_sell_out.notes IS 'Optional note from promotor about the sale';
