-- Phase 1 hardening (non-breaking): enable RLS and add safe baseline policies
-- Scope: chat_members, chat_rooms, message_reactions, kpi_ma_scores,
--        products, product_variants, store_groups, target_periods, user_targets

-- 1) Helper functions
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.role
  FROM public.users u
  WHERE u.id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.current_user_role() = 'admin'::public.user_role, false);
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_manager_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    public.current_user_role() IN ('admin'::public.user_role, 'manager'::public.user_role),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.is_elevated_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    public.current_user_role() IN (
      'admin'::public.user_role,
      'manager'::public.user_role,
      'spv'::public.user_role,
      'sator'::public.user_role
    ),
    false
  );
$$;

-- 2) Enable RLS
ALTER TABLE IF EXISTS public.chat_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.kpi_ma_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.store_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.target_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.user_targets ENABLE ROW LEVEL SECURITY;

-- 3) chat_members policies (replace recursive/fragile variants)
DROP POLICY IF EXISTS "Room admins can manage members" ON public.chat_members;
DROP POLICY IF EXISTS "Users can view memberships in their rooms" ON public.chat_members;
DROP POLICY IF EXISTS "Admins can manage all memberships" ON public.chat_members;
DROP POLICY IF EXISTS "Users can view own memberships" ON public.chat_members;
DROP POLICY IF EXISTS "Users can update own memberships" ON public.chat_members;

CREATE POLICY "Users can view own memberships"
ON public.chat_members
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_admin_user());

CREATE POLICY "Users can update own memberships"
ON public.chat_members
FOR UPDATE
TO authenticated
USING (user_id = auth.uid() OR public.is_admin_user())
WITH CHECK (user_id = auth.uid() OR public.is_admin_user());

CREATE POLICY "Admins can manage all memberships"
ON public.chat_members
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

-- 4) chat_rooms policies (keep intent explicit)
DROP POLICY IF EXISTS "Admins can manage all rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Users can view rooms they are members of" ON public.chat_rooms;

CREATE POLICY "Admins can manage all rooms"
ON public.chat_rooms
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "Users can view rooms they are members of"
ON public.chat_rooms
FOR SELECT
TO authenticated
USING (
  id IN (
    SELECT cm.room_id
    FROM public.chat_members cm
    WHERE cm.user_id = auth.uid()
      AND cm.left_at IS NULL
  )
  OR public.is_admin_user()
);

-- 5) message_reactions policies
DROP POLICY IF EXISTS "Users can manage reactions in their rooms" ON public.message_reactions;
DROP POLICY IF EXISTS "Users can view reactions in own rooms" ON public.message_reactions;
DROP POLICY IF EXISTS "Users can insert reactions in own rooms" ON public.message_reactions;
DROP POLICY IF EXISTS "Users can delete own reactions" ON public.message_reactions;

CREATE POLICY "Users can view reactions in own rooms"
ON public.message_reactions
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.chat_messages msg
    JOIN public.chat_members cm ON cm.room_id = msg.room_id
    WHERE msg.id = message_reactions.message_id
      AND cm.user_id = auth.uid()
      AND cm.left_at IS NULL
  )
  OR public.is_admin_user()
);

CREATE POLICY "Users can insert reactions in own rooms"
ON public.message_reactions
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND (
    EXISTS (
      SELECT 1
      FROM public.chat_messages msg
      JOIN public.chat_members cm ON cm.room_id = msg.room_id
      WHERE msg.id = message_reactions.message_id
        AND cm.user_id = auth.uid()
        AND cm.left_at IS NULL
    )
    OR public.is_admin_user()
  )
);

CREATE POLICY "Users can delete own reactions"
ON public.message_reactions
FOR DELETE
TO authenticated
USING (user_id = auth.uid() OR public.is_admin_user());

-- 6) products + product_variants (existing read policy may already exist; add write policy)
DROP POLICY IF EXISTS "Admins manage products" ON public.products;
DROP POLICY IF EXISTS "Admins manage product variants" ON public.product_variants;

CREATE POLICY "Admins manage products"
ON public.products
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "Admins manage product variants"
ON public.product_variants
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

-- 7) store_groups
DROP POLICY IF EXISTS "Authenticated read store_groups" ON public.store_groups;
DROP POLICY IF EXISTS "Admins manage store_groups" ON public.store_groups;

CREATE POLICY "Authenticated read store_groups"
ON public.store_groups
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins manage store_groups"
ON public.store_groups
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

-- 8) target_periods
DROP POLICY IF EXISTS "Authenticated read target_periods" ON public.target_periods;
DROP POLICY IF EXISTS "Admins manage target_periods" ON public.target_periods;

CREATE POLICY "Authenticated read target_periods"
ON public.target_periods
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins manage target_periods"
ON public.target_periods
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

-- 9) user_targets
DROP POLICY IF EXISTS "Users read own or elevated user_targets" ON public.user_targets;
DROP POLICY IF EXISTS "Admins or managers manage user_targets" ON public.user_targets;

CREATE POLICY "Users read own or elevated user_targets"
ON public.user_targets
FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_elevated_user());

CREATE POLICY "Admins or managers manage user_targets"
ON public.user_targets
FOR ALL
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

-- 10) kpi_ma_scores
DROP POLICY IF EXISTS "Users read own or elevated kpi_ma_scores" ON public.kpi_ma_scores;
DROP POLICY IF EXISTS "Elevated users manage kpi_ma_scores" ON public.kpi_ma_scores;

CREATE POLICY "Users read own or elevated kpi_ma_scores"
ON public.kpi_ma_scores
FOR SELECT
TO authenticated
USING (sator_id = auth.uid() OR public.is_elevated_user());

CREATE POLICY "Elevated users manage kpi_ma_scores"
ON public.kpi_ma_scores
FOR ALL
TO authenticated
USING (public.is_elevated_user())
WITH CHECK (public.is_elevated_user());
