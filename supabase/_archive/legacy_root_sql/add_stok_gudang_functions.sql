-- =====================================================
-- STOK GUDANG SYSTEM (FIXED V2)
-- Date: 30 January 2026
-- Description: Functions for bulk upserting warehouse stock.
--              FIXED: Used TEXT for return types to prevent 42804 type mismatch errors.
-- =====================================================

-- 1. TYPE DEFINITION FOR INPUT
DROP TYPE IF EXISTS stok_gudang_input_type CASCADE;
CREATE TYPE stok_gudang_input_type AS (
    product_name TEXT,
    variant_name TEXT,
    color TEXT,
    stok_gudang INTEGER,
    stok_otw INTEGER
);

-- 2. BULK UPSERT FUNCTION
CREATE OR REPLACE FUNCTION bulk_upsert_stok_gudang(
    p_sator_id UUID,
    p_tanggal DATE,
    p_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_product_id UUID;
    v_variant_id UUID;
    v_success_count INTEGER := 0;
    v_fail_count INTEGER := 0;
    v_errors TEXT[] := ARRAY[]::TEXT[];
    v_status TEXT; -- Changed to TEXT
    v_price NUMERIC;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
    LOOP
        BEGIN
            -- Priority: Use IDs if provided
            IF (v_item->>'product_id') IS NOT NULL THEN
                v_product_id := (v_item->>'product_id')::UUID;
                v_variant_id := (v_item->>'variant_id')::UUID;
            ELSE
                RAISE EXCEPTION 'Product ID not provided for %', v_item->>'product_name';
            END IF;

            -- Calculate Status based on Price
            SELECT price INTO v_price FROM product_variants WHERE id = v_variant_id;
            
            IF (v_item->>'stok_gudang')::INTEGER = 0 THEN
                v_status := 'kosong';
            ELSIF v_price <= 2000000 THEN
                IF (v_item->>'stok_gudang')::INTEGER < 100 THEN v_status := 'tipis'; ELSE v_status := 'cukup'; END IF;
            ELSIF v_price <= 3000000 THEN
                IF (v_item->>'stok_gudang')::INTEGER <= 50 THEN v_status := 'tipis'; ELSE v_status := 'cukup'; END IF;
            ELSIF v_price <= 5000000 THEN
                IF (v_item->>'stok_gudang')::INTEGER <= 20 THEN v_status := 'tipis'; ELSE v_status := 'cukup'; END IF;
            ELSE 
                IF (v_item->>'stok_gudang')::INTEGER <= 10 THEN v_status := 'tipis'; ELSE v_status := 'cukup'; END IF;
            END IF;

            -- Upsert
            INSERT INTO stok_gudang_harian (
                product_id,
                variant_id,
                tanggal,
                stok_gudang,
                stok_otw,
                status,
                created_by,
                updated_at
            ) VALUES (
                v_product_id,
                v_variant_id,
                p_tanggal,
                COALESCE((v_item->>'stok_gudang')::INTEGER, 0),
                COALESCE((v_item->>'stok_otw')::INTEGER, 0),
                v_status::VARCHAR(20), -- Cast back if column is strict varchar
                p_sator_id,
                NOW()
            )
            ON CONFLICT (product_id, variant_id, tanggal) 
            DO UPDATE SET
                stok_gudang = EXCLUDED.stok_gudang,
                stok_otw = EXCLUDED.stok_otw,
                status = EXCLUDED.status,
                updated_at = NOW();

            v_success_count := v_success_count + 1;

        EXCEPTION WHEN OTHERS THEN
            v_fail_count := v_fail_count + 1;
            v_errors := array_append(v_errors, 'Error on ' || COALESCE(v_item->>'product_name', 'Unknown') || ': ' || SQLERRM);
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'success', v_success_count,
        'failed', v_fail_count,
        'errors', v_errors
    );
END;
$$;

-- 3. HELPER: GET ALL PRODUCTS FOR MAPPING (FIXED TYPES)
-- Changed all VARCHAR return types to TEXT to handle any column type safely
DROP FUNCTION IF EXISTS get_products_for_mapping();

CREATE OR REPLACE FUNCTION get_products_for_mapping()
RETURNS TABLE (
    product_id UUID,
    variant_id UUID,
    product_name TEXT,   -- Changed from VARCHAR to TEXT
    variant_name TEXT,   -- Changed from VARCHAR to TEXT
    color TEXT,          -- Changed from VARCHAR to TEXT
    full_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id as product_id,
        pv.id as variant_id,
        p.model_name::TEXT as product_name, -- Explicit cast to be safe
        pv.ram_rom::TEXT as variant_name,   -- Explicit cast to be safe
        pv.color::TEXT as color,            -- Explicit cast to be safe
        (p.model_name || ' ' || pv.ram_rom || ' ' || pv.color)::TEXT as full_name
    FROM products p
    JOIN product_variants pv ON p.id = pv.product_id;
END;
$$;

-- Permissions
GRANT EXECUTE ON FUNCTION bulk_upsert_stok_gudang(UUID, DATE, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION get_products_for_mapping() TO authenticated;
