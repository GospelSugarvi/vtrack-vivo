-- Migration: Personal Bonus Target for Promotors
-- Date: 29 Januari 2026
-- Purpose: Allow promotors to set their own bonus target goal

-- 1. Add personal_bonus_target column to users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS personal_bonus_target BIGINT DEFAULT 0;

-- Comment for clarity
COMMENT ON COLUMN public.users.personal_bonus_target IS 'Target bonus yang diharapkan promotor setiap bulan (dalam Rupiah). Diisi sendiri oleh promotor.';

-- 2. Create function to update personal bonus target
CREATE OR REPLACE FUNCTION public.update_personal_bonus_target(
    p_user_id UUID,
    p_target_amount BIGINT
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.users 
    SET personal_bonus_target = p_target_amount,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.update_personal_bonus_target(UUID, BIGINT) TO authenticated;

-- 3. Update get_promotor_bonus_summary to include personal target
-- (This assumes the original function exists)
