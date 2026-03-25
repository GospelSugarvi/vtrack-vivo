-- Fokus Products Detail System
-- Store target breakdown per fokus product for each user

-- ==========================================
-- STEP 1: Add column for fokus products detail
-- ==========================================
-- Add target_fokus_detail column (JSONB) to store breakdown per product
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'user_targets' AND column_name = 'target_fokus_detail') THEN
        ALTER TABLE user_targets ADD COLUMN target_fokus_detail JSONB DEFAULT '{}';
    END IF;
END $$;

-- ==========================================
-- STEP 2: Add is_fokus flag to products table (if not exists)
-- ==========================================
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'products' AND column_name = 'is_fokus') THEN
        ALTER TABLE products ADD COLUMN is_fokus BOOLEAN DEFAULT false;
    END IF;
END $$;

-- ==========================================
-- STEP 3: Function to get active fokus products
-- ==========================================
CREATE OR REPLACE FUNCTION get_active_fokus_products()
RETURNS TABLE (
    product_id UUID,
    model_name TEXT,
    series TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id as product_id,
        p.model_name,
        p.series
    FROM products p
    WHERE p.is_fokus = true
      AND p.status = 'active'
      AND p.deleted_at IS NULL
    ORDER BY p.series, p.model_name;
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- STEP 4: Grant permissions
-- ==========================================
GRANT EXECUTE ON FUNCTION get_active_fokus_products() TO authenticated;

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Fokus products detail system installed!' as status;
SELECT 'Products table now has is_fokus flag' as note1;
SELECT 'User targets can store fokus detail breakdown' as note2;
