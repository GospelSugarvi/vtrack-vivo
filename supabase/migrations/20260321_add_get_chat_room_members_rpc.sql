SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_chat_room_members(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  nickname TEXT,
  role TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.chat_members cm
    WHERE cm.room_id = p_room_id
      AND cm.user_id = p_user_id
      AND cm.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'User is not a member of this room';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.full_name::TEXT,
    u.nickname::TEXT,
    u.role::TEXT
  FROM public.chat_members cm
  JOIN public.users u ON u.id = cm.user_id
  WHERE cm.room_id = p_room_id
    AND cm.left_at IS NULL
    AND COALESCE(u.status, 'active') = 'active'
  ORDER BY COALESCE(NULLIF(u.nickname, ''), u.full_name), u.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_chat_room_members(UUID, UUID) TO authenticated;
