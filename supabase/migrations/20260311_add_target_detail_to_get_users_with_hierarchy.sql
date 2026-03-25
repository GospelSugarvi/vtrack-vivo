-- Migration: add target detail columns to get_users_with_hierarchy

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
    target_fokus_detail JSONB,
    target_special_detail JSONB,
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
            COALESCE(ut.target_sell_in, 0)::BIGINT as target_sell_in,
            COALESCE(ut.target_sell_out, 0)::BIGINT as target_sell_out,
            COALESCE(ut.target_fokus, 0) as target_fokus,
            COALESCE(ut.target_sellout_asp, 0) as target_sellout_asp,
            COALESCE(ut.target_special, 0) as target_special,
            COALESCE(ut.target_fokus_detail, '{}'::jsonb) as target_fokus_detail,
            COALESCE(ut.target_special_detail, '{}'::jsonb) as target_special_detail,
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
            COALESCE(ut.target_sell_in, 0)::BIGINT as target_sell_in,
            COALESCE(ut.target_sell_out, 0)::BIGINT as target_sell_out,
            COALESCE(ut.target_fokus, 0) as target_fokus,
            COALESCE(ut.target_sellout_asp, 0) as target_sellout_asp,
            COALESCE(ut.target_special, 0) as target_special,
            COALESCE(ut.target_fokus_detail, '{}'::jsonb) as target_fokus_detail,
            COALESCE(ut.target_special_detail, '{}'::jsonb) as target_special_detail,
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
            COALESCE(ut.target_sell_in, 0)::BIGINT as target_sell_in,
            COALESCE(ut.target_sell_out, 0)::BIGINT as target_sell_out,
            COALESCE(ut.target_fokus, 0) as target_fokus,
            COALESCE(ut.target_sellout_asp, 0) as target_sellout_asp,
            COALESCE(ut.target_special, 0) as target_special,
            COALESCE(ut.target_fokus_detail, '{}'::jsonb) as target_fokus_detail,
            COALESCE(ut.target_special_detail, '{}'::jsonb) as target_special_detail,
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
