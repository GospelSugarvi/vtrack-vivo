-- Migration: 20260312_expose_special_rewards.sql
-- Expose special rewards config for sator/spv

CREATE OR REPLACE FUNCTION public.get_special_rewards_by_role(
  p_role TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (
    SELECT COALESCE(json_agg(
      json_build_object(
        'id', sr.id,
        'role', sr.role,
        'min_unit', sr.min_unit,
        'max_unit', sr.max_unit,
        'reward_amount', sr.reward_amount,
        'penalty_threshold', sr.penalty_threshold,
        'penalty_amount', sr.penalty_amount,
        'data_source', sr.data_source,
        'product_name', p.model_name,
        'bundle_name', fb.bundle_name,
        'special_bundle_name', sb.bundle_name
      )
    ), '[]'::json)
    FROM public.special_rewards sr
    LEFT JOIN public.products p ON p.id = sr.product_id
    LEFT JOIN public.fokus_bundles fb ON fb.id = sr.bundle_id
    LEFT JOIN public.special_focus_bundles sb ON sb.id = sr.special_bundle_id
    WHERE sr.role = p_role
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_special_rewards_by_role(TEXT) TO authenticated;
