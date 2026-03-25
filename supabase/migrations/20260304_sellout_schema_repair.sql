-- Sell-out schema repair for environments that missed earlier migrations.
-- Safe to run multiple times.

ALTER TABLE public.sales_sell_out
ADD COLUMN IF NOT EXISTS customer_name VARCHAR(100),
ADD COLUMN IF NOT EXISTS customer_phone VARCHAR(20),
ADD COLUMN IF NOT EXISTS customer_type VARCHAR(20) DEFAULT 'toko',
ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.sales_sell_out
DROP CONSTRAINT IF EXISTS check_customer_type;

ALTER TABLE public.sales_sell_out
ADD CONSTRAINT check_customer_type
CHECK (customer_type IN ('vip_call', 'toko'));

CREATE INDEX IF NOT EXISTS idx_sales_customer_type
ON public.sales_sell_out(customer_type);
