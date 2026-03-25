-- Prevent duplicate validation items in the same validation session
-- Add unique constraint on (validation_id, stok_id)
ALTER TABLE stock_validation_items
ADD CONSTRAINT unique_stock_per_validation UNIQUE (validation_id, stok_id);

-- Optional: To prevent validating same stock multiple times a day across DIFFERENT sessions is harder in SQL without triggers.
-- But the App logic filters out already validated items, so this constraint fixes the "double tap" issue within a single batch.
