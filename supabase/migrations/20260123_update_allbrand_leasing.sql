-- Update AllBrand table to change leasing from options to sales count

-- Drop old column
ALTER TABLE allbrand_reports DROP COLUMN IF EXISTS leasing_options;

-- Add new column for leasing sales
ALTER TABLE allbrand_reports ADD COLUMN IF NOT EXISTS leasing_sales JSONB DEFAULT '{}'::jsonb;

-- Update comment
COMMENT ON COLUMN allbrand_reports.leasing_sales IS 'Sales count per leasing provider (JSONB): {"HCI": 5, "Kredivo": 3, ...}';
