-- Migration: 20260311_focus_targets_specials.sql
-- Add per-period fokus flags + special targets + ASP target

-- 1) Extend fokus_products with flags for detail target and special type
ALTER TABLE public.fokus_products
ADD COLUMN IF NOT EXISTS is_detail_target BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_special BOOLEAN DEFAULT false;

-- 2) Extend user_targets with new targets (ASP & special)
ALTER TABLE public.user_targets
ADD COLUMN IF NOT EXISTS target_sellout_asp NUMERIC DEFAULT 0 CHECK (target_sellout_asp >= 0),
ADD COLUMN IF NOT EXISTS target_special INTEGER DEFAULT 0 CHECK (target_special >= 0);

-- 3) Fokus products by period helper
CREATE OR REPLACE FUNCTION public.get_fokus_products_by_period(
    p_period_id UUID
)
RETURNS TABLE (
    product_id UUID,
    model_name TEXT,
    series TEXT,
    is_detail_target BOOLEAN,
    is_special BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id AS product_id,
        p.model_name,
        p.series,
        COALESCE(fp.is_detail_target, false) AS is_detail_target,
        COALESCE(fp.is_special, false) AS is_special
    FROM public.fokus_products fp
    JOIN public.products p ON p.id = fp.product_id
    WHERE fp.period_id = p_period_id
      AND p.status = 'active'
      AND p.deleted_at IS NULL
    ORDER BY p.series, p.model_name;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.get_fokus_products_by_period(UUID) TO authenticated;

-- 4) Update bulk_set_targets with new optional params
DROP FUNCTION IF EXISTS public.bulk_set_targets(UUID[], UUID, NUMERIC, INTEGER, INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION public.bulk_set_targets(
    p_user_ids UUID[],
    p_period_id UUID,
    p_target_omzet NUMERIC DEFAULT NULL,
    p_target_fokus_total INTEGER DEFAULT NULL,
    p_target_tiktok INTEGER DEFAULT NULL,
    p_target_follower INTEGER DEFAULT NULL,
    p_target_vast INTEGER DEFAULT NULL,
    p_target_sell_in BIGINT DEFAULT NULL,
    p_target_sell_out BIGINT DEFAULT NULL,
    p_target_fokus INTEGER DEFAULT NULL,
    p_target_sellout_asp NUMERIC DEFAULT NULL,
    p_target_special INTEGER DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    -- Insert or update targets for each user
    INSERT INTO public.user_targets (
        user_id,
        period_id,
        target_omzet,
        target_fokus_total,
        target_tiktok,
        target_follower,
        target_vast,
        target_sell_in,
        target_sell_out,
        target_fokus,
        target_sellout_asp,
        target_special,
        updated_at
    )
    SELECT
        unnest(p_user_ids),
        p_period_id,
        COALESCE(p_target_omzet, 0),
        COALESCE(p_target_fokus_total, 0),
        COALESCE(p_target_tiktok, 0),
        COALESCE(p_target_follower, 0),
        COALESCE(p_target_vast, 0),
        COALESCE(p_target_sell_in, 0),
        COALESCE(p_target_sell_out, 0),
        COALESCE(p_target_fokus, 0),
        COALESCE(p_target_sellout_asp, 0),
        COALESCE(p_target_special, 0),
        NOW()
    ON CONFLICT (user_id, period_id) DO UPDATE SET
        target_omzet = COALESCE(p_target_omzet, user_targets.target_omzet),
        target_fokus_total = COALESCE(p_target_fokus_total, user_targets.target_fokus_total),
        target_tiktok = COALESCE(p_target_tiktok, user_targets.target_tiktok),
        target_follower = COALESCE(p_target_follower, user_targets.target_follower),
        target_vast = COALESCE(p_target_vast, user_targets.target_vast),
        target_sell_in = COALESCE(p_target_sell_in, user_targets.target_sell_in),
        target_sell_out = COALESCE(p_target_sell_out, user_targets.target_sell_out),
        target_fokus = COALESCE(p_target_fokus, user_targets.target_fokus),
        target_sellout_asp = COALESCE(p_target_sellout_asp, user_targets.target_sellout_asp),
        target_special = COALESCE(p_target_special, user_targets.target_special),
        updated_at = NOW();

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION public.bulk_set_targets(
    UUID[], UUID, NUMERIC, INTEGER, INTEGER, INTEGER, INTEGER, BIGINT, BIGINT, INTEGER, NUMERIC, INTEGER
) TO authenticated;

-- 5) Update get_users_with_hierarchy to include new fields
DROP FUNCTION IF EXISTS public.get_users_with_hierarchy(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.get_users_with_hierarchy(
    p_period_id UUID,
    p_role TEXT DEFAULT 'promotor'
)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    role TEXT,
    sator_id UUID,
    sator_name TEXT,
    spv_id UUID,
    spv_name TEXT,
    target_omzet NUMERIC,
    target_fokus_total INTEGER,
    target_tiktok INTEGER,
    target_follower INTEGER,
    target_vast INTEGER,
    target_sell_in BIGINT,
    target_sell_out BIGINT,
    target_fokus INTEGER,
    target_sellout_asp NUMERIC,
    target_special INTEGER,
    has_target BOOLEAN
) AS $$
BEGIN
    IF p_role = 'promotor' THEN
        RETURN QUERY
        SELECT 
            u.id as user_id,
            u.full_name,
            u.role::TEXT,
            sator.id as sator_id,
            sator.full_name as sator_name,
            spv.id as spv_id,
            spv.full_name as spv_name,
            COALESCE(ut.target_omzet, 0) as target_omzet,
            COALESCE(ut.target_fokus_total, 0) as target_fokus_total,
            COALESCE(ut.target_tiktok, 0) as target_tiktok,
            COALESCE(ut.target_follower, 0) as target_follower,
            COALESCE(ut.target_vast, 0) as target_vast,
            COALESCE(ut.target_sell_in, 0) as target_sell_in,
            COALESCE(ut.target_sell_out, 0) as target_sell_out,
            COALESCE(ut.target_fokus, 0) as target_fokus,
            COALESCE(ut.target_sellout_asp, 0) as target_sellout_asp,
            COALESCE(ut.target_special, 0) as target_special,
            (ut.id IS NOT NULL) as has_target
        FROM public.users u
        LEFT JOIN public.hierarchy_sator_promotor hsp ON hsp.promotor_id = u.id AND hsp.active = true
        LEFT JOIN public.users sator ON sator.id = hsp.sator_id
        LEFT JOIN public.hierarchy_spv_sator hss ON hss.sator_id = sator.id AND hss.active = true
        LEFT JOIN public.users spv ON spv.id = hss.spv_id
        LEFT JOIN public.user_targets ut ON ut.user_id = u.id AND ut.period_id = p_period_id
        WHERE u.role = 'promotor'
          AND u.deleted_at IS NULL
        ORDER BY sator.full_name NULLS LAST, u.full_name;
        
    ELSIF p_role = 'sator' THEN
        RETURN QUERY
        SELECT 
            u.id as user_id,
            u.full_name,
            u.role::TEXT,
            NULL::UUID as sator_id,
            NULL::TEXT as sator_name,
            spv.id as spv_id,
            spv.full_name as spv_name,
            COALESCE(ut.target_omzet, 0) as target_omzet,
            COALESCE(ut.target_fokus_total, 0) as target_fokus_total,
            COALESCE(ut.target_tiktok, 0) as target_tiktok,
            COALESCE(ut.target_follower, 0) as target_follower,
            COALESCE(ut.target_vast, 0) as target_vast,
            COALESCE(ut.target_sell_in, 0) as target_sell_in,
            COALESCE(ut.target_sell_out, 0) as target_sell_out,
            COALESCE(ut.target_fokus, 0) as target_fokus,
            COALESCE(ut.target_sellout_asp, 0) as target_sellout_asp,
            COALESCE(ut.target_special, 0) as target_special,
            (ut.id IS NOT NULL) as has_target
        FROM public.users u
        LEFT JOIN public.hierarchy_spv_sator hss ON hss.sator_id = u.id AND hss.active = true
        LEFT JOIN public.users spv ON spv.id = hss.spv_id
        LEFT JOIN public.user_targets ut ON ut.user_id = u.id AND ut.period_id = p_period_id
        WHERE u.role = 'sator'
          AND u.deleted_at IS NULL
        ORDER BY spv.full_name NULLS LAST, u.full_name;
        
    ELSE -- SPV
        RETURN QUERY
        SELECT 
            u.id as user_id,
            u.full_name,
            u.role::TEXT,
            NULL::UUID as sator_id,
            NULL::TEXT as sator_name,
            NULL::UUID as spv_id,
            NULL::TEXT as spv_name,
            COALESCE(ut.target_omzet, 0) as target_omzet,
            COALESCE(ut.target_fokus_total, 0) as target_fokus_total,
            COALESCE(ut.target_tiktok, 0) as target_tiktok,
            COALESCE(ut.target_follower, 0) as target_follower,
            COALESCE(ut.target_vast, 0) as target_vast,
            COALESCE(ut.target_sell_in, 0) as target_sell_in,
            COALESCE(ut.target_sell_out, 0) as target_sell_out,
            COALESCE(ut.target_fokus, 0) as target_fokus,
            COALESCE(ut.target_sellout_asp, 0) as target_sellout_asp,
            COALESCE(ut.target_special, 0) as target_special,
            (ut.id IS NOT NULL) as has_target
        FROM public.users u
        LEFT JOIN public.user_targets ut ON ut.user_id = u.id AND ut.period_id = p_period_id
        WHERE u.role = 'spv'
          AND u.deleted_at IS NULL
        ORDER BY u.full_name;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.get_users_with_hierarchy(UUID, TEXT) TO authenticated;
