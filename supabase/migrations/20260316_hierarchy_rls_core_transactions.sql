-- Consolidate hierarchy-aware RLS for core transaction tables.
-- Goals:
-- 1. Centralize role and hierarchy checks in helper functions.
-- 2. Align core transaction tables with hierarchy-based access rules.
-- 3. Keep direct table writes least-privilege while preserving RPC-based workflows.

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

CREATE OR REPLACE FUNCTION public.is_manager_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.current_user_role() = 'manager'::public.user_role, false);
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

CREATE OR REPLACE FUNCTION public.is_spv_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.current_user_role() = 'spv'::public.user_role, false);
$$;

CREATE OR REPLACE FUNCTION public.is_sator_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.current_user_role() = 'sator'::public.user_role, false);
$$;

CREATE OR REPLACE FUNCTION public.is_promotor_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.current_user_role() = 'promotor'::public.user_role, false);
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

CREATE OR REPLACE FUNCTION public.current_user_promotor_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH accessible AS (
    SELECT u.id
    FROM public.users u
    WHERE public.is_admin_or_manager_user()
      AND u.role = 'promotor'::public.user_role

    UNION

    SELECT auth.uid()
    WHERE public.is_promotor_user()

    UNION

    SELECT hsp.promotor_id
    FROM public.hierarchy_sator_promotor hsp
    WHERE hsp.active = true
      AND hsp.sator_id = auth.uid()

    UNION

    SELECT hsp.promotor_id
    FROM public.hierarchy_spv_sator hss
    JOIN public.hierarchy_sator_promotor hsp
      ON hsp.sator_id = hss.sator_id
     AND hsp.active = true
    WHERE hss.active = true
      AND hss.spv_id = auth.uid()
  )
  SELECT COALESCE(array_agg(DISTINCT id), ARRAY[]::uuid[])
  FROM accessible;
$$;

CREATE OR REPLACE FUNCTION public.current_user_sator_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH accessible AS (
    SELECT u.id
    FROM public.users u
    WHERE public.is_admin_or_manager_user()
      AND u.role = 'sator'::public.user_role

    UNION

    SELECT auth.uid()
    WHERE public.is_sator_user()

    UNION

    SELECT hss.sator_id
    FROM public.hierarchy_spv_sator hss
    WHERE hss.active = true
      AND hss.spv_id = auth.uid()
  )
  SELECT COALESCE(array_agg(DISTINCT id), ARRAY[]::uuid[])
  FROM accessible;
$$;

CREATE OR REPLACE FUNCTION public.current_user_store_ids()
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH accessible AS (
    SELECT s.id
    FROM public.stores s
    WHERE public.is_admin_or_manager_user()

    UNION

    SELECT aps.store_id
    FROM public.assignments_promotor_store aps
    WHERE aps.active = true
      AND aps.promotor_id = auth.uid()

    UNION

    SELECT ass.store_id
    FROM public.assignments_sator_store ass
    WHERE ass.active = true
      AND ass.sator_id = auth.uid()

    UNION

    SELECT aps.store_id
    FROM public.hierarchy_sator_promotor hsp
    JOIN public.assignments_promotor_store aps
      ON aps.promotor_id = hsp.promotor_id
     AND aps.active = true
    WHERE hsp.active = true
      AND hsp.sator_id = auth.uid()

    UNION

    SELECT ass.store_id
    FROM public.hierarchy_spv_sator hss
    JOIN public.assignments_sator_store ass
      ON ass.sator_id = hss.sator_id
     AND ass.active = true
    WHERE hss.active = true
      AND hss.spv_id = auth.uid()

    UNION

    SELECT aps.store_id
    FROM public.hierarchy_spv_sator hss
    JOIN public.hierarchy_sator_promotor hsp
      ON hsp.sator_id = hss.sator_id
     AND hsp.active = true
    JOIN public.assignments_promotor_store aps
      ON aps.promotor_id = hsp.promotor_id
     AND aps.active = true
    WHERE hss.active = true
      AND hss.spv_id = auth.uid()
  )
  SELECT COALESCE(array_agg(DISTINCT id), ARRAY[]::uuid[])
  FROM accessible;
$$;

CREATE OR REPLACE FUNCTION public.can_access_sator(p_sator_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL OR p_sator_id IS NULL THEN false
    WHEN public.is_admin_or_manager_user() THEN true
    WHEN public.is_sator_user() AND auth.uid() = p_sator_id THEN true
    WHEN public.is_spv_user() THEN EXISTS (
      SELECT 1
      FROM public.hierarchy_spv_sator hss
      WHERE hss.active = true
        AND hss.spv_id = auth.uid()
        AND hss.sator_id = p_sator_id
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_promotor(p_promotor_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL OR p_promotor_id IS NULL THEN false
    WHEN public.is_admin_or_manager_user() THEN true
    WHEN auth.uid() = p_promotor_id THEN true
    WHEN public.is_sator_user() THEN EXISTS (
      SELECT 1
      FROM public.hierarchy_sator_promotor hsp
      WHERE hsp.active = true
        AND hsp.sator_id = auth.uid()
        AND hsp.promotor_id = p_promotor_id
    )
    WHEN public.is_spv_user() THEN EXISTS (
      SELECT 1
      FROM public.hierarchy_spv_sator hss
      JOIN public.hierarchy_sator_promotor hsp
        ON hsp.sator_id = hss.sator_id
       AND hsp.active = true
      WHERE hss.active = true
        AND hss.spv_id = auth.uid()
        AND hsp.promotor_id = p_promotor_id
    )
    ELSE false
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_store(p_store_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL OR p_store_id IS NULL THEN false
    WHEN public.is_admin_or_manager_user() THEN true
    ELSE p_store_id = ANY(public.current_user_store_ids())
  END;
$$;

ALTER TABLE IF EXISTS public.sales_sell_out ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sales_sell_in ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sell_in_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sell_in_order_items ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy_record record;
  target_table text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'sales_sell_out',
    'sales_sell_in',
    'sell_in_orders',
    'sell_in_order_items'
  ]
  LOOP
    FOR policy_record IN
      SELECT p.policyname
      FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = target_table
    LOOP
      EXECUTE format(
        'DROP POLICY IF EXISTS %I ON public.%I',
        policy_record.policyname,
        target_table
      );
    END LOOP;
  END LOOP;
END $$;

CREATE POLICY "sales_sell_out_select_hierarchy"
ON public.sales_sell_out
FOR SELECT
TO authenticated
USING (
  deleted_at IS NULL
  AND (
    public.can_access_promotor(promotor_id)
    OR public.can_access_store(store_id)
  )
);

CREATE POLICY "sales_sell_out_insert_own"
ON public.sales_sell_out
FOR INSERT
TO authenticated
WITH CHECK (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
    AND public.can_access_promotor(promotor_id)
    AND public.can_access_store(store_id)
  )
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "sales_sell_out_update_admin"
ON public.sales_sell_out
FOR UPDATE
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

CREATE POLICY "sales_sell_out_delete_admin"
ON public.sales_sell_out
FOR DELETE
TO authenticated
USING (public.is_admin_or_manager_user());

CREATE POLICY "sales_sell_in_select_hierarchy"
ON public.sales_sell_in
FOR SELECT
TO authenticated
USING (
  deleted_at IS NULL
  AND (
    public.can_access_sator(sator_id)
    OR public.can_access_store(store_id)
  )
);

CREATE POLICY "sales_sell_in_insert_own"
ON public.sales_sell_in
FOR INSERT
TO authenticated
WITH CHECK (
  (
    public.is_sator_user()
    AND sator_id = auth.uid()
    AND public.can_access_sator(sator_id)
    AND public.can_access_store(store_id)
  )
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "sales_sell_in_update_admin"
ON public.sales_sell_in
FOR UPDATE
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

CREATE POLICY "sales_sell_in_delete_admin"
ON public.sales_sell_in
FOR DELETE
TO authenticated
USING (public.is_admin_or_manager_user());

CREATE POLICY "sell_in_orders_select_hierarchy"
ON public.sell_in_orders
FOR SELECT
TO authenticated
USING (
  public.can_access_sator(sator_id)
  OR public.can_access_store(store_id)
);

CREATE POLICY "sell_in_orders_insert_own"
ON public.sell_in_orders
FOR INSERT
TO authenticated
WITH CHECK (
  (
    public.is_sator_user()
    AND sator_id = auth.uid()
    AND public.can_access_sator(sator_id)
    AND public.can_access_store(store_id)
  )
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "sell_in_orders_update_admin"
ON public.sell_in_orders
FOR UPDATE
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

CREATE POLICY "sell_in_orders_delete_admin"
ON public.sell_in_orders
FOR DELETE
TO authenticated
USING (public.is_admin_or_manager_user());

CREATE POLICY "sell_in_order_items_select_hierarchy"
ON public.sell_in_order_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.sell_in_orders o
    WHERE o.id = sell_in_order_items.order_id
      AND (
        public.can_access_sator(o.sator_id)
        OR public.can_access_store(o.store_id)
      )
  )
);

CREATE POLICY "sell_in_order_items_insert_pending_owner"
ON public.sell_in_order_items
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.sell_in_orders o
    WHERE o.id = sell_in_order_items.order_id
      AND (
        (
          public.is_sator_user()
          AND o.sator_id = auth.uid()
          AND o.status = 'pending'
          AND public.can_access_store(o.store_id)
        )
        OR public.is_admin_or_manager_user()
      )
  )
);

CREATE POLICY "sell_in_order_items_update_pending_owner"
ON public.sell_in_order_items
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.sell_in_orders o
    WHERE o.id = sell_in_order_items.order_id
      AND (
        (
          public.is_sator_user()
          AND o.sator_id = auth.uid()
          AND o.status = 'pending'
          AND public.can_access_store(o.store_id)
        )
        OR public.is_admin_or_manager_user()
      )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.sell_in_orders o
    WHERE o.id = sell_in_order_items.order_id
      AND (
        (
          public.is_sator_user()
          AND o.sator_id = auth.uid()
          AND o.status = 'pending'
          AND public.can_access_store(o.store_id)
        )
        OR public.is_admin_or_manager_user()
      )
  )
);

CREATE POLICY "sell_in_order_items_delete_pending_owner"
ON public.sell_in_order_items
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.sell_in_orders o
    WHERE o.id = sell_in_order_items.order_id
      AND (
        (
          public.is_sator_user()
          AND o.sator_id = auth.uid()
          AND o.status = 'pending'
          AND public.can_access_store(o.store_id)
        )
        OR public.is_admin_or_manager_user()
      )
  )
);
