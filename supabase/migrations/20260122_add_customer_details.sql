-- Add Customer Details & Customer Type to Sales Sell Out
-- Requirement: 
-- 1. Customer Name & Phone
-- 2. Customer Type (VIP Call / User Toko)

ALTER TABLE sales_sell_out 
ADD COLUMN IF NOT EXISTS customer_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS customer_phone VARCHAR(20),
ADD COLUMN IF NOT EXISTS customer_type VARCHAR(20) DEFAULT 'toko'; -- 'vip_call' or 'toko'

-- Add constraint for customer_type
ALTER TABLE sales_sell_out 
DROP CONSTRAINT IF EXISTS check_customer_type;

ALTER TABLE sales_sell_out 
ADD CONSTRAINT check_customer_type CHECK (customer_type IN ('vip_call', 'toko'));

-- Index for analytics
CREATE INDEX IF NOT EXISTS idx_sales_customer_type ON sales_sell_out(customer_type);
