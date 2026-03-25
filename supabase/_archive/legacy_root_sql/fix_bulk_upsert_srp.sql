-- FIX function bulk_upsert_stok_gudang
-- Change 'price' column to 'srp' (based on error report)
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
    v_status TEXT;
    v_price NUMERIC;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
    LOOP
        BEGIN
            -- Priority: Use IDs if provided
            IF (v_item->>'product_id') IS NOT NULL AND (v_item->>'product_id') != 'null' THEN
                v_product_id := (v_item->>'product_id')::UUID;
                v_variant_id := (v_item->>'variant_id')::UUID;
            ELSE
                RAISE EXCEPTION 'Product ID not provided for %', v_item->>'product_name';
            END IF;

            -- Calculate Status based on Price (SRP)
            -- FIX: Changed 'price' to 'srp'
            SELECT srp INTO v_price FROM product_variants WHERE id = v_variant_id;
            
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
                v_status::VARCHAR(20),
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
