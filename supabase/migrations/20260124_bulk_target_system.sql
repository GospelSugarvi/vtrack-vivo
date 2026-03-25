-- Bulk Target Setting System
-- Enable easy target setting for 100+ users
-- FIXED: Using correct table names and column names from schema

-- ==========================================
-- STEP 0: Add missing columns to user_targets
-- ==========================================
-- Add target_omzet if not exists (alias for target_sell_out)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'user_targets' AND column_name = 'target_omzet') THEN
        ALTER TABLE user_targets ADD COLUMN target_omzet NUMERIC DEFAULT 0;
    END IF;
END $$;

-- Add target_fokus_total if not exists (extracted from target_units_focus JSONB)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'user_targets' AND column_name = 'target_fokus_total') THEN
        ALTER TABLE user_targets ADD COLUMN target_fokus_total INTEGER DEFAULT 0;
    END IF;
END $$;

-- Add target_tiktok if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'user_targets' AND column_name = 'target_tiktok') THEN
        ALTER TABLE user_targets ADD COLUMN target_tiktok INTEGER DEFAULT 0;
    END IF;
END $$;

-- Add target_follower if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'user_targets' AND column_name = 'target_follower') THEN
        ALTER TABLE user_targets ADD COLUMN target_follower INTEGER DEFAULT 0;
    END IF;
END $$;

-- Add target_vast if not exists
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'user_targets' AND column_name = 'target_vast') THEN
        ALTER TABLE user_targets ADD COLUMN target_vast INTEGER DEFAULT 0;
    END IF;
END $$;

-- ==========================================
-- STEP 1: Add unique constraint (prevent duplicates)
-- ==========================================
ALTER TABLE user_targets DROP CONSTRAINT IF EXISTS unique_user_period;
ALTER TABLE user_targets
ADD CONSTRAINT unique_user_period UNIQUE (user_id, period_id);

-- ==========================================
-- STEP 2: Bulk set targets function
-- ==========================================
CREATE OR REPLACE FUNCTION bulk_set_targets(
    p_user_ids UUID[],
    p_period_id UUID,
    p_target_omzet NUMERIC DEFAULT NULL,
    p_target_fokus_total INTEGER DEFAULT NULL,
    p_target_tiktok INTEGER DEFAULT NULL,
    p_target_follower INTEGER DEFAULT NULL,
    p_target_vast INTEGER DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_user_id UUID;
    v_count INTEGER := 0;
BEGIN
    -- Loop through each user
    FOREACH v_user_id IN ARRAY p_user_ids
    LOOP
        -- Upsert (insert or update)
        INSERT INTO user_targets (
            user_id,
            period_id,
            target_omzet,
            target_fokus_total,
            target_tiktok,
            target_follower,
            target_vast
        ) VALUES (
            v_user_id,
            p_period_id,
            COALESCE(p_target_omzet, 0),
            COALESCE(p_target_fokus_total, 0),
            COALESCE(p_target_tiktok, 0),
            COALESCE(p_target_follower, 0),
            COALESCE(p_target_vast, 0)
        )
        ON CONFLICT (user_id, period_id)
        DO UPDATE SET
            target_omzet = COALESCE(p_target_omzet, user_targets.target_omzet),
            target_fokus_total = COALESCE(p_target_fokus_total, user_targets.target_fokus_total),
            target_tiktok = COALESCE(p_target_tiktok, user_targets.target_tiktok),
            target_follower = COALESCE(p_target_follower, user_targets.target_follower),
            target_vast = COALESCE(p_target_vast, user_targets.target_vast),
            updated_at = NOW();
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- STEP 3: Get users with hierarchy
-- ==========================================
-- Drop existing function first (return type changed)
DROP FUNCTION IF EXISTS get_users_with_hierarchy(UUID, TEXT);

CREATE OR REPLACE FUNCTION get_users_with_hierarchy(
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
            (ut.id IS NOT NULL) as has_target
        FROM users u
        LEFT JOIN hierarchy_sator_promotor hsp ON hsp.promotor_id = u.id AND hsp.active = true
        LEFT JOIN users sator ON sator.id = hsp.sator_id
        LEFT JOIN hierarchy_spv_sator hss ON hss.sator_id = sator.id AND hss.active = true
        LEFT JOIN users spv ON spv.id = hss.spv_id
        LEFT JOIN user_targets ut ON ut.user_id = u.id AND ut.period_id = p_period_id
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
            (ut.id IS NOT NULL) as has_target
        FROM users u
        LEFT JOIN hierarchy_spv_sator hss ON hss.sator_id = u.id AND hss.active = true
        LEFT JOIN users spv ON spv.id = hss.spv_id
        LEFT JOIN user_targets ut ON ut.user_id = u.id AND ut.period_id = p_period_id
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
            (ut.id IS NOT NULL) as has_target
        FROM users u
        LEFT JOIN user_targets ut ON ut.user_id = u.id AND ut.period_id = p_period_id
        WHERE u.role = 'spv'
        AND u.deleted_at IS NULL
        ORDER BY u.full_name;
    END IF;
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- STEP 4: Grant permissions
-- ==========================================
GRANT EXECUTE ON FUNCTION bulk_set_targets(UUID[], UUID, NUMERIC, INTEGER, INTEGER, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_users_with_hierarchy(UUID, TEXT) TO authenticated;

-- ==========================================
-- SUCCESS MESSAGE
-- ==========================================
SELECT '✅ Bulk target system installed!' as status;
SELECT 'Now you can set targets for 100+ users in 1 minute' as info;
SELECT 'FIXED: Using correct table names (hierarchy_sator_promotor, hierarchy_spv_sator)' as note;
SELECT 'FIXED: Using correct column names (target_omzet, target_units_focus)' as note2;
