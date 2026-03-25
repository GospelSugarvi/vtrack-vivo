CREATE OR REPLACE FUNCTION public.get_sale_reaction_details(
  p_sale_id UUID
)
RETURNS TABLE (
  reaction_type TEXT,
  user_id UUID,
  user_name TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    fr.reaction_type,
    fr.user_id,
    u.full_name AS user_name,
    fr.created_at
  FROM public.feed_reactions fr
  JOIN public.users u ON u.id = fr.user_id
  WHERE fr.sale_id = p_sale_id
  ORDER BY fr.reaction_type, fr.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sale_reaction_details(UUID) TO authenticated;
