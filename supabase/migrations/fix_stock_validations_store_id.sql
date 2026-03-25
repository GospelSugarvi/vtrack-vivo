-- Add store_id column to stock_validations table if not exists

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'stock_validations'
        AND column_name = 'store_id'
    ) THEN
        ALTER TABLE stock_validations ADD COLUMN store_id UUID REFERENCES stores(id);
    END IF;
END $$;

-- Also verify/refresh schema cache by notifying pgrst? Usually not needed if run via dashboard.
COMMENT ON COLUMN stock_validations.store_id IS 'Store being validated';
